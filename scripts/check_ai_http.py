"""Exercise the AI HTTP boundary against loopback only, through the native CLI."""
import argparse
import gzip
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import socket
import subprocess
import threading

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / '_build/ai-http-acceptance'
REPORT = '本地 HTTP 验收：字段正常。'
MODEL = 'loopback-test-model'


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def read_body(handler):
    if handler.headers.get('Transfer-Encoding', '').lower() != 'chunked':
        return handler.rfile.read(int(handler.headers['Content-Length']))
    chunks = []
    while True:
        size = int(handler.rfile.readline().split(b';')[0], 16)
        if not size:
            while handler.rfile.readline() != b'\r\n':
                pass
            return b''.join(chunks)
        chunks.append(handler.rfile.read(size))
        require(handler.rfile.read(2) == b'\r\n', 'invalid request chunk')


class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, *_args):
        pass

    def do_POST(self):
        try:
            self.connection.settimeout(10)
            body = json.loads(read_body(self).decode('utf-8'))
            require(self.headers.get('Authorization') == 'Bearer loopback-dummy-key', 'authorization')
            require(self.headers.get('Content-Type') == 'application/json', 'content type')
            require(body['model'] == MODEL, 'model')
            require('中文' in json.dumps(body, ensure_ascii=False), 'UTF-8 input')
            self.server.observations.append(dict(path=self.path, body=body,
                accept_encoding=self.headers.get('Accept-Encoding')))
            if self.path == '/disconnect':
                self.close_connection = True
                self.connection.shutdown(socket.SHUT_RDWR)
                self.connection.close()
                return
            status = 429 if self.path == '/api-error' else 200
            payload = (dict(error=dict(message='local rate limit')) if status == 429 else
                       dict(choices=[dict(message=dict(content=REPORT))]))
            data = json.dumps(payload, ensure_ascii=False).encode('utf-8')
            if self.path == '/invalid-json':
                data = b'{'
            compressed = self.path in ('/gzip', '/chunked-gzip', '/corrupt-gzip')
            if compressed:
                require('gzip' in self.headers.get('Accept-Encoding', ''), 'gzip not negotiated')
                data = b'not gzip' if self.path == '/corrupt-gzip' else gzip.compress(data)
            chunked = self.path in ('/chunked', '/chunked-gzip')
            self.send_response(status)
            self.send_header('Content-Type', 'application/json; charset=utf-8')
            self.send_header('Connection', 'close')
            if compressed:
                self.send_header('Content-Encoding', 'gzip')
            if chunked:
                self.send_header('Transfer-Encoding', 'chunked')
            else:
                self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            if chunked:
                for start in range(0, len(data), 7):
                    chunk = data[start:start + 7]
                    self.wfile.write(f'{len(chunk):x}\r\n'.encode() + chunk + b'\r\n')
                self.wfile.write(b'0\r\n\r\n')
            else:
                self.wfile.write(data)
            self.wfile.flush()
            self.close_connection = True
        except Exception as error:
            self.server.errors.append(str(error))
            self.close_connection = True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cli', type=Path, required=True)
    args = parser.parse_args()
    cli = (ROOT / args.cli).resolve()
    OUTPUT.mkdir(parents=True, exist_ok=True)
    rows = []
    summary = dict(status='running', results=rows)
    summary_path = OUTPUT / 'summary.json'
    summary_path.write_text(json.dumps(summary), encoding='utf-8')
    require(cli.is_file(), f'missing native CLI: {cli}')
    server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    server.daemon_threads = True
    server.observations, server.errors = [], []
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    env = dict(os.environ, MOONJSON_AI_API_KEY='loopback-dummy-key')
    scenarios = [('/plain', 0, REPORT), ('/gzip', 0, REPORT),
                 ('/chunked', 0, REPORT), ('/chunked-gzip', 0, REPORT),
                 ('/api-error', 3, 'local rate limit'),
                 ('/invalid-json', 3, 'not valid JSON'),
                 ('/corrupt-gzip', 3, 'could not reach'),
                 ('/disconnect', 3, 'could not reach')]
    try:
        for route, expected, text in scenarios:
            name = route[1:]
            reasons = []
            try:
                before = len(server.observations)
                process = subprocess.run([str(cli), '--no-color', '--ai', '--model', MODEL,
                    '--ai-base-url', f'http://127.0.0.1:{server.server_port}{route}'],
                    cwd=ROOT, env=env, input='{"字段":"中文"}'.encode('utf-8'),
                    capture_output=True, timeout=15)
                (OUTPUT / (name + '.stdout')).write_bytes(process.stdout)
                (OUTPUT / (name + '.stderr')).write_bytes(process.stderr)
                require(process.returncode == expected, f'exit {process.returncode}, expected {expected}')
                selected = process.stdout if expected == 0 else process.stderr
                require(text in selected.decode('utf-8'), 'missing response/error diagnostic')
                require(len(server.observations) == before + 1, 'request was not received')
                require(not server.errors, repr(server.errors))
            except (OSError, ValueError, AssertionError, subprocess.TimeoutExpired) as error:
                reasons.append(str(error))
            rows.append(dict(name=name, expected_exit=expected, passed=not reasons, failures=reasons))
            print(('FAIL ' if reasons else 'PASS ') + name + (': ' + '; '.join(reasons) if reasons else ''))
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)
    summary.update(status='passed' if all(r['passed'] for r in rows) and not server.errors else 'failed',
                   executed=len(rows), passed=sum(r['passed'] for r in rows),
                   server_errors=server.errors, requests=server.observations)
    summary_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f"AI HTTP acceptance: {summary['passed']}/{len(rows)}; {summary['status']}")
    return 0 if summary['status'] == 'passed' else 1


if __name__ == '__main__':
    raise SystemExit(main())
