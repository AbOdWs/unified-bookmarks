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
        if is_running():
            self._respond(200, {'started': False, 'reason': 'already-running'})
            return
        # fire and forget; build-wiki.sh handles its own lock + logging
        subprocess.Popen(['/bin/bash', '/root/build-wiki.sh'],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True)
        self._respond(200, {'started': True})

    def log_message(self, *a):
        pass


HTTPServer(('0.0.0.0', 8767), Handler).serve_forever()
