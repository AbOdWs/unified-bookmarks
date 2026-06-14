from http.server import HTTPServer, BaseHTTPRequestHandler
import subprocess, json, os

LOCK = '/root/.build-wiki.lock'


def is_running():
    if not os.path.exists(LOCK):
        return False
    try:
        pid = int(open(LOCK).read().strip())
        os.kill(pid, 0)
        return True
    except Exception:
        return False


class Handler(BaseHTTPRequestHandler):
    def _respond(self, code, obj):
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(obj).encode())

    def do_GET(self):
        self._respond(200, {'running': is_running()})

    def do_POST(self):
        path = self.path.rstrip('/')
        length = int(self.headers.get('Content-Length', 0))
        raw = self.rfile.read(length).decode('utf-8', 'replace') if length else ''

        # فقيه planning endpoints — pass the idea/question via body {idea}
        if path.endswith('spec') or path.endswith('research'):
            try:
                idea = json.loads(raw).get('idea', '') if raw else ''
            except Exception:
                idea = raw
            with open('/root/.faqih-request.txt', 'w') as f:
                f.write(idea)
            mode = 'research' if path.endswith('research') else 'spec'
            subprocess.Popen(['/bin/bash', '/root/faqih-spec.sh', mode],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                             start_new_session=True)
            self._respond(200, {'started': True, 'agent': 'faqih', 'mode': mode})
            return

        # courier vs build-wiki
        script = '/root/courier-scan.sh' if path.endswith('courier') else '/root/build-wiki.sh'
        if script == '/root/build-wiki.sh' and is_running():
            self._respond(200, {'started': False, 'reason': 'already-running'})
            return
        subprocess.Popen(['/bin/bash', script],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True)
        self._respond(200, {'started': True, 'script': script})

    def log_message(self, *a):
        pass


HTTPServer(('0.0.0.0', 8767), Handler).serve_forever()
