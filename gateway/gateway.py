"""Day 31 developer assistant gateway. Python 3.10+, no third-party dependencies."""
import developer_assistant
import support_assistant
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

    def do_POST(self):
        supplied = self.headers.get('Authorization', '')
        identity = next((i for i, token in enumerate(TOKENS)
                         if hmac.compare_digest(supplied.encode(), ('Bearer ' + token).encode())), None)
        if identity is None:
            self.reply(401, {'error': 'Valid Bearer token required'})
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
