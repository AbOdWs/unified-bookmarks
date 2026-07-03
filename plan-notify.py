#!/usr/bin/env python3
# Sends a فقيه plan card to Telegram: preview + Obsidian link + GitHub button + a short
# stable #code + action buttons. Reused by faqih-spec.sh (new plans) and by
# build-trigger-api.py's /idea #code resume path (re-send an existing plan's card).
#
# Env:  NAME=<plan basename, no .md>   [HEADER=<extra first line>]
# The plan file may live anywhere under 01-Projects/ (_queue, _archive, _rejected).
import json, os, re, sys, glob, zlib, urllib.request, urllib.parse

KN  = '/root/knowledge'
cfg = json.load(open('/root/config.json'))
token = cfg['telegram_bot_token']
chat  = str(cfg['telegram_chat_id'])
vault = cfg.get('obsidian_vault_name', 'my-brain')
gh    = (cfg.get('github_base', '') or '').rstrip('/')

name   = os.environ.get('NAME', '').strip()
header = os.environ.get('HEADER', '').strip()
if not name:
    sys.exit(0)

cands = glob.glob(f'{KN}/01-Projects/**/{name}.md', recursive=True)
if not cands:
    sys.exit(0)
doc = cands[0]
rel = os.path.relpath(doc, KN)              # e.g. 01-Projects/_queue/xxx.md
content = open(doc, encoding='utf-8').read()


def he(s):
    return s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')


def section(txt, h):
    m = re.search(r'## ' + re.escape(h) + r'\n(.*?)(?=\n## |\Z)', txt, re.DOTALL)
    return m.group(1).strip() if m else ''


def b36(n):
    A = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    s = ''
    while n and len(s) < 4:
        n, r = divmod(n, 36)
        s = A[r] + s
    return (s or '0').rjust(4, '0')


# ── stable short code in frontmatter (assign once, collision-checked) ────────
m = re.search(r'^code:\s*(\S+)', content, re.M)
if m:
    code = m.group(1)
else:
    taken = {}
    for f in glob.glob(f'{KN}/01-Projects/**/*.md', recursive=True):
        try:
            mm = re.search(r'^code:\s*(\S+)', open(f, encoding='utf-8').read(), re.M)
        except Exception:
            mm = None
        if mm:
            taken[mm.group(1)] = f
    salt = 0
    while True:
        seed = name if salt == 0 else f'{name}#{salt}'
        code = b36(zlib.crc32(seed.encode()) & 0xFFFFFFFF)
        if code not in taken or taken[code] == doc:
            break
        salt += 1
    content = (re.sub(r'^---\n', f'---\ncode: {code}\n', content, count=1)
               if content.startswith('---') else f'---\ncode: {code}\n---\n' + content)
    open(doc, 'w', encoding='utf-8').write(content)

goal = section(content, 'الهدف')[:150]
wiki = section(content, 'ما تعرفه مسبقاً')[:350]
plan = section(content, 'الخطة')[:500]

parts = []
if header:
    parts.append(header)
parts.append(f'📋 <b>خطة فقيه</b>  ·  🔖 <b>#{code}</b>')
if goal:
    parts.append(f'\n🎯 <b>الهدف:</b> {he(goal)}')
if wiki:
    parts.append(f'\n📚 <b>من قبوك:</b>\n{he(wiki)}')
if plan:
    parts.append(f'\n<b>الخطة:</b>\n{he(plan)}')

rel_noext = rel[:-3] if rel.endswith('.md') else rel
obs = f'obsidian://open?vault={urllib.parse.quote(vault)}&file={urllib.parse.quote(rel_noext)}'
parts.append(f'\n📱 <b>افتح في Obsidian</b> (انسخ):\n<code>{he(obs)}</code>')
parts.append(f'\nللرجوع لاحقاً: <code>/idea #{code}</code>')
msg = '\n'.join(parts)

rows = []
if gh:
    gh_url = gh + '/' + '/'.join(urllib.parse.quote(p) for p in rel.split('/'))
    rows.append([{'text': '📄 افتح الملاحظة (GitHub)', 'url': gh_url}])
rows.append([
    {'text': '✅ اعتمد',       'callback_data': f'idea_approve:{name}'},
    {'text': '🔄 أعد التفكير', 'callback_data': f'idea_rethink:{name}'},
])
rows.append([
    {'text': '⏸ لاحقاً',       'callback_data': f'idea_hold:{name}'},
    {'text': '🗑 تجاهل',        'callback_data': f'idea_discard:{name}'},
])

payload = {'chat_id': chat, 'text': msg, 'parse_mode': 'HTML',
           'reply_markup': {'inline_keyboard': rows}, 'disable_web_page_preview': True}
req = urllib.request.Request(f'https://api.telegram.org/bot{token}/sendMessage',
                             data=json.dumps(payload).encode(),
                             headers={'Content-Type': 'application/json'})
try:
    urllib.request.urlopen(req, timeout=10)
except Exception as e:
    with open('/root/faqih.log', 'a') as f:
        f.write(f'plan-notify error ({name}): {e}\n')
