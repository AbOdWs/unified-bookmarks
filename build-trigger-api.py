from http.server import HTTPServer, BaseHTTPRequestHandler
import subprocess, json, os, re, shutil, glob, urllib.request, urllib.parse

LOCK = '/root/.build-wiki.lock'
PROJECTS = '/root/knowledge/01-Projects'


def _tg(text):
    try:
        cfg = json.load(open('/root/config.json'))
        data = urllib.parse.urlencode({'chat_id': cfg['telegram_chat_id'], 'text': text}).encode()
        urllib.request.urlopen('https://api.telegram.org/bot' + cfg['telegram_bot_token'] + '/sendMessage',
                               data=data, timeout=10)
    except Exception:
        pass


def resume_by_code(code):
    """Find the plan whose frontmatter `code:` matches, and re-send its card."""
    code = code.upper()
    for f in glob.glob(f'{PROJECTS}/**/*.md', recursive=True):
        try:
            m = re.search(r'^code:\s*(\S+)', open(f, encoding='utf-8').read(), re.MULTILINE)
        except Exception:
            m = None
        if m and m.group(1).upper() == code:
            name = os.path.basename(f)[:-3]
            subprocess.Popen(['python3', '/root/plan-notify.py'],
                             env={**os.environ, 'NAME': name},
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                             start_new_session=True)
            return True
    _tg(f'لم أجد خطة بالكود #{code}. اكتب /idea <فكرة> لبدء واحدة جديدة.')
    return False


def find_slug_by_code(code):
    """Return the plan slug (basename, no .md) whose frontmatter code: matches, else None."""
    code = code.upper()
    for f in glob.glob(f'{PROJECTS}/**/*.md', recursive=True):
        try:
            m = re.search(r'^code:\s*(\S+)', open(f, encoding='utf-8').read(), re.MULTILINE)
        except Exception:
            m = None
        if m and m.group(1).upper() == code:
            return os.path.basename(f)[:-3]
    return None


# text-command approval (no n8n callbacks): "/idea <keyword> #CODE [feedback]"
_IDEA_ACTIONS = {
    'approve': 'approve', 'موافق': 'approve', 'موافقة': 'approve', 'اعتمد': 'approve', 'أعتمد': 'approve', 'ok': 'approve',
    'hold': 'hold', 'لاحقا': 'hold', 'لاحقاً': 'hold', 'تأجيل': 'hold', 'أجل': 'hold',
    'discard': 'discard', 'تجاهل': 'discard', 'احذف': 'discard', 'حذف': 'discard',
    'rethink': 'rethink', 'أعد': 'rethink', 'اعد': 'rethink', 'راجع': 'rethink',
}


def apply_idea_action(action, code, feedback=''):
    """Do the same thing the inline buttons do, resolved by #code, and confirm via Telegram."""
    slug = find_slug_by_code(code)
    C = code.upper()
    if not slug:
        _tg(f'لم أجد خطة بالكود #{C}. أرسل /idea #{C} للتأكد، أو /idea <فكرة> لبدء جديدة.')
        return {'ok': False, 'reason': 'code not found', 'code': C}
    doc = f'/root/knowledge/01-Projects/_queue/{slug}.md'
    if action == 'approve':
        _update_frontmatter_status(doc, 'approved')
        subprocess.Popen(['/bin/bash', '/root/idea-execute.sh'],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        _tg(f'✅ اعتُمدت #{C} — وكيل بدأ التنفيذ على فرع معزول. ستصلك النتيجة عند الانتهاء.')
        return {'ok': True, 'action': 'approve', 'slug': slug}
    if action == 'hold':
        _update_frontmatter_status(doc, 'hold')
        _tg(f'⏸ حُفظت #{C} بحالة hold. أرسل /idea #{C} لفتحها لاحقاً.')
        return {'ok': True, 'action': 'hold', 'slug': slug}
    if action == 'discard':
        archive = f'/root/knowledge/01-Projects/_archive/{slug}.md'
        if os.path.exists(doc):
            os.makedirs(os.path.dirname(archive), exist_ok=True)
            shutil.move(doc, archive)
        _tg(f'🗑 تجاهلت #{C} (نُقلت إلى الأرشيف).')
        return {'ok': True, 'action': 'discard', 'slug': slug}
    if action == 'rethink':
        original = open(doc).read() if os.path.exists(doc) else ''
        combined = original + (f'\n\n## ملاحظة المراجعة\n{feedback}' if feedback else '')
        with open('/root/.faqih-request.txt', 'w') as f:
            f.write(combined or feedback or slug)
        subprocess.Popen(['/bin/bash', '/root/faqih-spec.sh', 'idea'],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        tail = ' مع ملاحظتك' if feedback else ''
        _tg(f'🔄 أعيد التفكير في #{C}{tail} — ستصلك خطة محدّثة خلال دقائق.')
        return {'ok': True, 'action': 'rethink', 'slug': slug}
    return {'ok': False, 'reason': 'unknown action'}


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
            # "/idea #CODE" — resume an existing plan (re-send its card) instead of creating one
            mcode = re.match(r'^#\s*([0-9A-Za-z]{2,8})$', idea.strip())
            if mcode:
                found = resume_by_code(mcode.group(1))
                self._respond(200, {'resumed': found, 'code': mcode.group(1).upper()})
                return
            # "/idea <keyword> #CODE [feedback]" — approve/hold/discard/rethink by text (no buttons)
            mact = re.match(r'^(\S+)\s+#\s*([0-9A-Za-z]{2,8})\b\s*(.*)$', idea.strip(), re.DOTALL)
            if mact and _IDEA_ACTIONS.get(mact.group(1).strip().lower()):
                result = apply_idea_action(_IDEA_ACTIONS[mact.group(1).strip().lower()],
                                           mact.group(2), mact.group(3).strip())
                self._respond(200, result)
                return
            # Archive the raw idea straight into processed/ (not the top-level watch dir)
            # so the cron watcher — which scans raw/ideas/*.md — can't pick it up and run
            # فقيه a second time. فقيه reads the text from .faqih-request.txt below anyway.
            ideas_dir = '/root/knowledge/raw/ideas/processed'
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
