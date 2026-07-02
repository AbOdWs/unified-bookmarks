from http.server import HTTPServer, BaseHTTPRequestHandler
import subprocess, json, os, re, shutil

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


def _update_frontmatter_status(doc_path, new_status):
    if not os.path.exists(doc_path):
        return False
    content = open(doc_path).read()
    content = re.sub(r'^status:\s*\S+', f'status: {new_status}', content, flags=re.MULTILINE)
    with open(doc_path, 'w') as f:
        f.write(content)
    return True


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

        # ── فقيه planning endpoints ───────────────────────────────────────────
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

        # ── Ideas pipeline ────────────────────────────────────────────────────

        # POST /idea  {idea: "text"}  — write to raw/ideas/ and trigger فقيه
        if path.endswith('/idea'):
            try:
                data = json.loads(raw) if raw else {}
                idea = data.get('idea', '').strip()
            except Exception:
                idea = raw.strip()
            if not idea:
                self._respond(400, {'error': 'no idea provided'})
                return
            ideas_dir = '/root/knowledge/raw/ideas'
            os.makedirs(ideas_dir, exist_ok=True)
            date_str = subprocess.check_output(['date', '+%Y-%m-%d']).decode().strip()
            slug = re.sub(r'[^\w؀-ۿ-]', '-', idea[:40].lower()).strip('-')
            fname = f"{ideas_dir}/{date_str}-{slug}.md"
            with open(fname, 'w') as f:
                f.write(f"---\ndate: {date_str}\nsource: telegram\n---\n\n{idea}\n")
            with open('/root/.faqih-request.txt', 'w') as f:
                f.write(idea)
            subprocess.Popen(['/bin/bash', '/root/faqih-spec.sh', 'idea'],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                             start_new_session=True)
            self._respond(200, {'started': True, 'agent': 'فقيه', 'mode': 'idea'})
            return

        # POST /idea-approve  {slug: "filename"}  — approve plan and trigger وكيل
        if path.endswith('/idea-approve'):
            try:
                slug = json.loads(raw).get('slug', '') if raw else ''
            except Exception:
                slug = ''
            doc = f"/root/knowledge/01-Projects/_queue/{slug}.md"
            updated = _update_frontmatter_status(doc, 'approved')
            subprocess.Popen(['/bin/bash', '/root/idea-execute.sh'],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                             start_new_session=True)
            self._respond(200, {'started': True, 'agent': 'وكيل', 'doc_updated': updated})
            return

        # POST /idea-hold  {slug: "filename"}  — mark status: hold
        if path.endswith('/idea-hold'):
            try:
                slug = json.loads(raw).get('slug', '') if raw else ''
            except Exception:
                slug = ''
            doc = f"/root/knowledge/01-Projects/_queue/{slug}.md"
            updated = _update_frontmatter_status(doc, 'hold')
            self._respond(200, {'held': True, 'doc_updated': updated})
            return

        # POST /idea-discard  {slug: "filename"}  — archive the plan
        if path.endswith('/idea-discard'):
            try:
                slug = json.loads(raw).get('slug', '') if raw else ''
            except Exception:
                slug = ''
            doc = f"/root/knowledge/01-Projects/_queue/{slug}.md"
            archive = f"/root/knowledge/01-Projects/_archive/{slug}.md"
            discarded = False
            if os.path.exists(doc):
                os.makedirs(os.path.dirname(archive), exist_ok=True)
                shutil.move(doc, archive)
                discarded = True
            self._respond(200, {'discarded': discarded})
            return

        # POST /idea-rethink  {slug: "filename", feedback: "text"}  — re-run فقيه with feedback
        if path.endswith('/idea-rethink'):
            try:
                data = json.loads(raw) if raw else {}
                slug = data.get('slug', '')
                feedback = data.get('feedback', '').strip()
            except Exception:
                slug = feedback = ''
            doc = f"/root/knowledge/01-Projects/_queue/{slug}.md"
            original = ''
            if os.path.exists(doc):
                try:
                    original = open(doc).read()
                except Exception:
                    pass
            combined = original
            if feedback:
                combined += f"\n\n## ملاحظة المراجعة\n{feedback}"
            with open('/root/.faqih-request.txt', 'w') as f:
                f.write(combined or feedback)
            subprocess.Popen(['/bin/bash', '/root/faqih-spec.sh', 'idea'],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                             start_new_session=True)
            self._respond(200, {'started': True, 'agent': 'فقيه', 'mode': 'rethink'})
            return

        # ── courier / build-wiki ──────────────────────────────────────────────
        if path.endswith('courier'):
            try:
                topic = json.loads(raw).get('topic', '') if raw else ''
            except Exception:
                topic = ''
            with open('/root/.courier-topic.txt', 'w') as f:
                f.write(topic or '')
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
