"""Day 31 developer assistant gateway. Python 3.10+, no third-party dependencies."""
import developer_assistant
import support_assistant
import file_assistant
import secrets
import collections
import hmac
import json
import os
import socket
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MODEL = 'qwen3:4b'
MAX_BODY = 32768
MAX_MESSAGES = 24
MAX_CONTEXT_BYTES = 6000
CONTEXT_TOKENS = 8192
OUTPUT_TOKENS = 512
RATE = 6
WINDOW = 60
GENERATION_TIMEOUT = 150
QUEUE_TIMEOUT = 160
TOKENS = tuple(t.strip() for t in os.environ.get('GATEWAY_TOKENS', '').split(',') if t.strip())
RATE_LOCK = threading.Lock()
RECENT = collections.defaultdict(collections.deque)
SLOTS = threading.BoundedSemaphore(4)  # one active request + three waiting
GENERATION = threading.Lock()
OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))


JOBS = {}
JOB_LOCK = threading.Lock()


class Handler(BaseHTTPRequestHandler):
    server_version = 'PrivateGateway'

    def setup(self):
        super().setup()
        self.connection.settimeout(10)

    def log_message(self, *_):
        pass  # Never log credentials, prompts or answers.

    def reply(self, status, data, retry=None):
        body = json.dumps(data, ensure_ascii=False).encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Connection', 'close')
        if retry is not None:
            self.send_header('Retry-After', str(retry))
        self.end_headers()
        self.close_connection = True
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError, socket.timeout):
            pass

    def files(self, identity):
        try:
            length = int(self.headers.get('Content-Length', '0'))
            if self.headers.get('Transfer-Encoding') or not 0 < length <= MAX_BODY:
                raise ValueError('Invalid body')
            data = json.loads(self.rfile.read(length))
            action = data.get('action')
            if action == 'start':
                question = data.get('question')
                if not isinstance(question, str) or not 1 <= len(question) <= 6000:
                    raise ValueError('Invalid goal')
                with JOB_LOCK:
                    now = time.monotonic()
                    for key in list(JOBS):
                        if JOBS[key]['expires'] < now and JOBS[key]['done']:
                            del JOBS[key]
                    if len(JOBS) >= 16 or any(j['owner'] == identity and not j['done'] for j in JOBS.values()):
                        raise ValueError('File task already running or capacity reached')
                    job_id = secrets.token_urlsafe(32)
                    job = {'owner': identity, 'expires': now + 3600, 'done': False, 'trace': [], 'started': now,
                           'progress': {'phase': 'Ожидание очереди Ollama', 'step': 0}}
                    JOBS[job_id] = job
                def work():
                    try:
                        if not GENERATION.acquire(timeout=QUEUE_TIMEOUT):
                            raise TimeoutError('Queue timeout')
                        try:
                            job['result'] = file_assistant.run(question, identity, job['trace'], job['progress'])
                        finally:
                            GENERATION.release()
                    except (socket.timeout, TimeoutError):
                        job['error'] = 'Ollama не завершила шаг за отведённое время. Файлы не записаны.'
                    except ValueError as error:
                        job['error'] = 'Ошибка ответа Ollama: ' + str(error)[:200] + '. Файлы не записаны.'
                    except Exception:
                        job['error'] = 'File assistant failed. Check MCP/Ollama; no unapproved writes.'
                    finally:
                        job['finished'] = time.monotonic()
                        job['done'] = True
                threading.Thread(target=work, daemon=True).start()
                self.reply(200, {'job': job_id})
            elif action == 'status':
                with JOB_LOCK:
                    job = JOBS.get(data.get('job')) if data.get('job') else next(
                        (j for j in reversed(list(JOBS.values())) if j['owner'] == identity), None)
                    if not job or job['owner'] != identity:
                        raise ValueError('Unknown job')
                    result = {k: v for k, v in job.items() if k not in ('owner', 'expires', 'started', 'finished')}
                    result['elapsed_seconds'] = int(job.get('finished', time.monotonic()) - job['started'])
                self.reply(200, result)
            elif action in ('approve', 'cancel'):
                self.reply(200, file_assistant.decide(data.get('proposal'), action == 'approve', identity))
            else:
                raise ValueError('Invalid action')
        except (ValueError, TypeError, OSError, KeyError):
            self.reply(400, {'error': 'File request failed or proposal stale; request a fresh preview.'})

    def do_POST(self):
        supplied = self.headers.get('Authorization', '')
        identity = next((i for i, token in enumerate(TOKENS)
                         if hmac.compare_digest(supplied.encode(), ('Bearer ' + token).encode())), None)
        if identity is None:
            self.reply(401, {'error': 'Valid Bearer token required'})
            return
        if self.path == '/v1/files':
            self.files(identity)
            return
        if self.path != '/v1/chat':
            self.reply(404, {'error': 'Unknown endpoint'})
            return
        now = time.monotonic()
        with RATE_LOCK:
            recent = RECENT[identity]
            while recent and recent[0] <= now - WINDOW:
                recent.popleft()
            limited = len(recent) >= RATE
            retry = max(1, int(WINDOW - (now - recent[0])) + 1) if limited else None
            if not limited:
                recent.append(now)
        if limited:
            self.reply(429, {'error': 'Rate limit: 6 requests per 60 seconds per token'}, retry)
            return
        try:
            if self.headers.get('Transfer-Encoding'):
                raise ValueError('Chunked requests are not supported')
            length = int(self.headers.get('Content-Length', '0'))
            if not 0 < length <= MAX_BODY:
                self.reply(413, {'error': 'Body must be 1–32768 bytes'})
                return
            if self.headers.get_content_type() != 'application/json':
                self.reply(415, {'error': 'Use application/json'})
                return
            raw = self.rfile.read(length)
            if len(raw) != length:
                raise ValueError('Incomplete body')
            data = json.loads(raw)
            if (not isinstance(data, dict) or 'messages' not in data
                    or set(data) - {'messages', 'mode', 'ticket_id'}):
                raise ValueError('Only messages is accepted')
            mode = data.get('mode', 'chat')
            ticket_id = data.get('ticket_id')
            if mode not in ('chat', 'support') or (mode == 'support' and
                    (type(ticket_id) is not int or ticket_id <= 0)):
                raise ValueError('Invalid support ticket')
            messages = data['messages']
            if not isinstance(messages, list) or not 1 <= len(messages) <= MAX_MESSAGES:
                raise ValueError('Provide 1–24 messages')
            for i, message in enumerate(messages):
                expected = 'user' if i % 2 == 0 else 'assistant'
                if (not isinstance(message, dict) or set(message) != {'role', 'content'}
                        or message['role'] != expected
                        or not isinstance(message['content'], str)
                        or not message['content'].strip()):
                    raise ValueError('Messages must alternate user/assistant with nonempty content')
            if messages[-1]['role'] != 'user':
                raise ValueError('Last message must be user')
            if sum(len(m['content'].encode('utf-8')) for m in messages) > MAX_CONTEXT_BYTES:
                self.reply(413, {'error': 'Context exceeds 6000 UTF-8 bytes; start a new chat'})
                return
        except (ValueError, UnicodeError):
            self.reply(400, {'error': 'Invalid JSON or message history'})
            return
        except (socket.timeout, OSError):
            self.reply(408, {'error': 'Request body timeout'})
            return
        if not SLOTS.acquire(blocking=False):
            self.reply(503, {'error': 'Queue full; retry later'}, 10)
            return
        try:
            if not GENERATION.acquire(timeout=QUEUE_TIMEOUT):
                self.reply(503, {'error': 'Queue wait expired; retry later'}, 10)
                return
            try:
                if mode == 'support':
                    answer = support_assistant.answer(ticket_id, messages)
                    self.reply(200, {'model': MODEL, 'message': {'role': 'assistant', 'content': answer},
                                     'done_reason': 'stop'})
                    return
                latest = messages[-1]['content'].strip()
                if latest == '/help' or latest.startswith('/help ' ) or latest.startswith('/help\n'):
                    answer = developer_assistant.answer(latest[5:].strip())
                    self.reply(200, {'model': MODEL, 'message': {'role': 'assistant', 'content': answer},
                                     'done_reason': 'stop'})
                    return
                payload = json.dumps({'model': MODEL, 'messages': messages,
                    'stream': False, 'think': False,
                    'options': {'num_ctx': CONTEXT_TOKENS, 'num_predict': OUTPUT_TOKENS,
                                'temperature': 0.6}}).encode()
                request = urllib.request.Request('http://127.0.0.1:11434/api/chat',
                    data=payload, headers={'Content-Type': 'application/json'}, method='POST')
                with OPENER.open(request, timeout=GENERATION_TIMEOUT) as response:
                    result = json.loads(response.read(262145))
                answer = result.get('message', {}).get('content')
                if result.get('done') is not True or not isinstance(answer, str) or not answer.strip():
                    raise ValueError('Invalid upstream response')
                self.reply(200, {'model': MODEL, 'message': {'role': 'assistant', 'content': answer},
                                 'done_reason': result.get('done_reason')})
            except (socket.timeout, TimeoutError):
                self.reply(504, {'error': 'Local generation timed out'})
            except (urllib.error.URLError, OSError, ValueError, AttributeError, KeyError, TypeError):
                self.reply(502, {'error': 'Assistant unavailable: check Ollama models, MCP server and documentation; response must have valid sources'})
            finally:
                GENERATION.release()
        finally:
            SLOTS.release()


if __name__ == '__main__':
    if not TOKENS or any(len(token) < 32 or not token.isascii() for token in TOKENS):
        raise SystemExit('Set GATEWAY_TOKENS to comma-separated ASCII secrets, each >=32 characters')
    server = ThreadingHTTPServer(('127.0.0.1', 8080), Handler)
    server.daemon_threads = True
    print('Gateway: http://127.0.0.1:8080/v1/chat; model qwen3:4b', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.server_close()
