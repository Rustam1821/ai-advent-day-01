"""Confined file operations. Invoked only by the existing Dart MCP server."""
import difflib
import hashlib
import hmac
import json
import os
from pathlib import Path
import re
import stat
import sys

ROOT = Path(__file__).resolve().parent.parent
TOOLS = ('list_files', 'search_text', 'read_file', 'get_diff', 'write_file')
EXTENSIONS = {'.md', '.dart', '.py', '.yaml', '.yml', '.json', '.txt', '.toml', '.xml', '.html', '.css', '.js', '.kt', '.swift'}
DENIED = {'build', 'node_modules', 'secrets', 'credentials', 'keys', 'vendor'}


def parts(path):
    if not isinstance(path, str) or not path or path.startswith('/') or '\\' in path:
        raise ValueError('Expected project-relative path')
    items = path.split('/')
    if any(not p or p in ('.', '..') or p.startswith('.') or p.lower() in DENIED or
           re.search(r'(secret|credential|password|token|private.key|id_rsa|id_ed25519|keystore)', p, re.I)
           for p in items) or Path(path).suffix.lower() not in EXTENSIONS:
        raise ValueError('Protected or unsupported path')
    return items


def parent(path):
    items = parts(path)
    fd = os.open(ROOT, os.O_RDONLY | os.O_DIRECTORY)
    try:
        for item in items[:-1]:
            child = os.open(item, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            os.close(fd)
            fd = child
        return fd, items[-1]
    except Exception:
        os.close(fd)
        raise


def read(path):
    fd, name = parent(path)
    try:
        try:
            file = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=fd)
        except FileNotFoundError:
            return None
        with os.fdopen(file, 'rb') as stream:
            info = os.fstat(stream.fileno())
            if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or info.st_size > 64000:
                raise ValueError('Not a single-link text file <=64KB')
            raw = stream.read(64001)
            if len(raw) > 64000 or b'\0' in raw:
                raise ValueError('Binary or oversized file')
            return raw.decode('utf-8')
    finally:
        os.close(fd)


def digest(content):
    return hashlib.sha256(json.dumps(content, ensure_ascii=False).encode()).hexdigest()


def signed(args):
    return json.dumps({k: args[k] for k in ('path', 'content', 'expected')}, sort_keys=True, ensure_ascii=False).encode()


def execute(tool, args):
    if tool in ('list_files', 'search_text'):
        query = args.get('query', '')
        if not isinstance(query, str) or (tool == 'search_text' and not query):
            raise ValueError('Expected query')
        results = []
        catalog = []
        scanned = 0
        for directory, dirs, files in os.walk(ROOT, followlinks=False):
            dirs[:] = sorted(d for d in dirs if not d.startswith('.') and d.lower() not in DENIED and not Path(directory, d).is_symlink())
            for name in sorted(files):
                path = Path(directory, name).relative_to(ROOT).as_posix()
                try:
                    parts(path)
                    if tool == 'list_files':
                        if read(path) is not None:
                            if len(catalog) < 100:
                                catalog.append(path)
                            if query.lower() in path.lower():
                                results.append(path)
                    else:
                        content = read(path)
                        if content is not None:
                            results.extend({'path': path, 'line': i, 'text': line[:400]} for i, line in enumerate(content.splitlines(), 1) if query.lower() in line.lower())
                except (ValueError, OSError, UnicodeError):
                    continue
                scanned += 1
                if len(results) >= 100 or scanned >= 3000:
                    return {'results': results[:100], 'truncated': True,
                            **({'catalog': catalog} if tool == 'list_files' else {})}
        return {'results': results, 'truncated': False,
                **({'catalog': catalog, 'catalog_truncated': len(catalog) == 100} if tool == 'list_files' else {})}
    path = args['path']
    before = read(path)
    if tool == 'read_file':
        if before is None:
            raise ValueError('File does not exist')
        return {'path': path, 'content': before, 'expected': digest(before)}
    content = args['content']
    if not isinstance(content, str) or len(content.encode()) > 64000 or '\0' in content:
        raise ValueError('Expected UTF-8 text <=64KB')
    expected = digest(before)
    diff = ''.join(difflib.unified_diff((before or '').splitlines(keepends=True), content.splitlines(keepends=True), fromfile=path if before is not None else '/dev/null', tofile=path))
    if tool == 'get_diff' or (tool == 'write_file' and 'approval' not in args):
        return {'path': path, 'diff': diff, 'expected': expected, 'changed': before != content}
    if tool != 'write_file':
        raise ValueError('Unknown tool')
    secret = os.environ.get('FILE_APPROVAL_SECRET', '')
    signature = hmac.new(secret.encode(), signed(args), hashlib.sha256).hexdigest()
    if len(secret) < 32 or not hmac.compare_digest(signature, args.get('approval', '')):
        raise ValueError('User approval required')
    if expected != args['expected']:
        raise ValueError('File changed since preview; request a fresh diff')
    if before == content:
        return {'path': path, 'saved': False, 'diff': ''}
    fd, name = parent(path)
    try:
        # Exclusive creation / no-follow plus inode identity protects path replacement.
        flags = os.O_WRONLY | os.O_NOFOLLOW | os.O_NONBLOCK
        file = os.open(name, flags | (os.O_CREAT | os.O_EXCL if before is None else 0), 0o644, dir_fd=fd)
        with os.fdopen(file, 'wb') as stream:
            info = os.fstat(stream.fileno())
            current = os.stat(name, dir_fd=fd, follow_symlinks=False)
            if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or info.st_ino != current.st_ino or (before is not None and read(path) != before):
                raise ValueError('Concurrent file modification')
            stream.write(content.encode())
            stream.truncate()
            stream.flush()
            os.fsync(stream.fileno())
    finally:
        os.close(fd)
    return {'path': path, 'saved': True, 'diff': diff}


if __name__ == '__main__':
    try:
        request = json.load(sys.stdin)
        print(json.dumps(execute(request['tool'], request['arguments']), ensure_ascii=False))
    except Exception as error:
        print(json.dumps({'error': str(error)}))
        sys.exit(1)
