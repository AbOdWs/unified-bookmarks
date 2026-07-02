#!/bin/bash
# فقيه — researcher/planner.
# Modes: spec | research | idea
#   spec     — turns a Telegram /spec command into a requirements draft
#   research — writes a research report to wiki/synthesis/
#   idea     — reads from raw/ideas/, cross-references wiki/, produces a plan with action buttons
export NVM_DIR=/root/.nvm
export PATH="$HOME/.local/bin:$PATH"
export CLAUDE_CODE_OAUTH_TOKEN=$(tr -d '[:space:]' < /root/.claude-token)
LOG=/root/faqih.log
cd /root/knowledge || exit 1
MODE="${1:-spec}"
IDEA=$(cat /root/.faqih-request.txt 2>/dev/null)
[ -z "$IDEA" ] && exit 0

TOKEN=$(python3 -c "import json;print(json.load(open('/root/config.json'))['telegram_bot_token'])")
CHAT=$(python3 -c "import json;print(json.load(open('/root/config.json'))['telegram_chat_id'])")

if [ "$MODE" = "research" ]; then
  TASK="أنت فقيه (اقرأ AIOS/agents/faqih.md أولاً). سؤال البحث: «$IDEA». اكتب تقريراً في wiki/synthesis/<تاريخ>-<slug>.md بقالب تقريرك: السؤال / الخيارات / المقايضات / قيودي (ميزانية، منطقة، بنيتي الحالية إن عُرفت) / التوصية / درجة الثقة وما تجهله / المصادر. اعرض المقايضات لا الأحكام، وصرّح بما لا تعرفه. لا تنفّذ شيئاً. سجّل في AIOS/agent-log.md. لا تلمس raw."
  HEAD="research"

elif [ "$MODE" = "idea" ]; then
  TASK="أنت فقيه (اقرأ AIOS/agents/faqih.md أولاً).

النص المُقدَّم (قد يحوي فكرة واحدة أو عدة أفكار منفصلة):
«$IDEA»

الخطوة ٠ — افصل الأفكار: حدّد كم فكرة مستقلة قابلة للتنفيذ يحويها النص. الأفكار المنفصلة موضوعياً تُكتب كمستندات منفصلة (مستند لكل فكرة). الفكرة الواحدة ولو كانت طويلة تبقى مستنداً واحداً. الحد الأقصى ٥ أفكار في الدفعة الواحدة؛ إن زادت فعالِج الأهم خمساً وسجّل الباقي في AIOS/agent-log.md.

ثم لكل فكرة مستقلة نفّذ الخطوات ١–٣ التالية بالكامل وأنشئ لها مستنداً مستقلاً:

الخطوة ١ — ابحث في قبو المعرفة:
استخدم Glob وGrep وRead لتحديد كل ما يتصل بالفكرة في: (أ) بطاقات wiki/، و(ب) ملفات مشاريعك القائمة في 01-Projects/*.md (المستوى الأعلى فقط — تجاهل _queue و_archive و_rejected). لكل عنصر ذي صلة اكتب: اسمه [[name]] + جملة تشرح صلته بالفكرة. وإذا كانت الفكرة تخص مشروعاً قائماً، وضّح صراحةً هل هي امتداد له أم مشروع جديد منفصل.

الخطوة ٢ — اكتب مستند الخطة في 01-Projects/_queue/<YYYY-MM-DD>-<slug>.md
حيث <slug> إنجليزي قصير (≤ 30 حرفاً، حروف صغيرة وشرطات فقط — لا عربية، لأنه يُستخدم في أزرار تيليغرام محدودة الطول).
بالترويسة YAML الكاملة:
title: <عنوان موجز للفكرة>
status: draft
agent: فقيه
date: <اليوم>

ثم بهذه الأقسام بالترتيب:
## ما تعرفه مسبقاً
(بطاقات wiki/ ذات الصلة — اذكر كل واحدة باسمها [[...]] وجملة صلتها. إن لم يوجد شيء: اكتب «لا يوجد في القبو بعد — فرصة لبناء معرفة جديدة»)

## الفكرة
(صياغة الفكرة بالكامل كما وردت + أي سياق مستنتج)

## الهدف
(جملة واحدة محددة: «بناء X بحيث Y»)

## الخطة
(خطوات مرتّبة ومحددة — كل خطوة قابلة للتنفيذ وحدها)

## خارج النطاق صراحةً
(ما لن يُبنى في هذه الدورة)

## المخاطر
(أبرز ما قد يعثر التنفيذ)

## تعريف «نسخة أولى منجزة»
(جملة واحدة واضحة)

الخطوة ٣ — سجّل في AIOS/agent-log.md.

القواعد الصارمة: فقيه يخطّط ولا ينفّذ أبداً. لا تلمس raw. هذا المستند هو ما يوافق عليه عبدالله قبل أي تنفيذ."
  HEAD="idea"

else
  TASK="أنت فقيه (اقرأ AIOS/agents/faqih.md أولاً). الفكرة: «$IDEA». حوّلها إلى **مستند متطلبات** في 01-Projects/_queue/<تاريخ>-<slug>.md بترويسة فيها 'status: draft' و 'agent: فقيه'، وبقالب المتطلبات: الهدف بجملة / السياق / داخل النطاق / **خارج النطاق صراحة** / الوكلاء الفرعيون المطلوبون / الخطوات / تعريف «نسخة أولى منجزة» / المخاطر. فقيه **يخطط ولا ينفّذ أبداً** — هذا المستند هو ما يوقّع عليه عبدالله. لا تلمس raw. سجّل في AIOS/agent-log.md."
  HEAD="spec"
fi

# snapshot the queue BEFORE the run so we can notify for exactly the docs فقيه creates
# (idea mode may yield several plans from one multi-idea message)
QUEUE_DIR="01-Projects/_queue"
BEFORE=$(ls "$QUEUE_DIR"/*.md 2>/dev/null | sort)

echo "$(date -u +%FT%TZ) START faqih $MODE: ${IDEA:0:80}" >> "$LOG"
OUT=$(timeout 900 claude -p "$TASK" --allowedTools "Read,Write,Edit,Glob,Grep,WebSearch,WebFetch" --permission-mode acceptEdits 2>&1)
echo "$OUT" >> "$LOG"
echo "$(date -u +%FT%TZ) END faqih $MODE" >> "$LOG"

# ── Notification ────────────────────────────────────────────────────────────────

if [ "$HEAD" = "research" ]; then
  NEW=$(ls -t wiki/synthesis/*.md 2>/dev/null | head -1)
  NAME=$(basename "$NEW" .md 2>/dev/null)
  MSG="🔎 *فقيه* — تقرير بحث جاهز: ${NAME}"
  curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${CHAT}" --data-urlencode "text=${MSG}" \
    -d "parse_mode=Markdown" >/dev/null
  exit 0
fi

# spec and idea modes: notify for EACH new plan doc فقيه created (idea mode can yield several)
AFTER=$(ls "$QUEUE_DIR"/*.md 2>/dev/null | sort)
NEWFILES=$(comm -13 <(printf '%s\n' "$BEFORE") <(printf '%s\n' "$AFTER") | sed '/^$/d')
# fallback: if none detected as new (e.g. فقيه edited an existing draft), use the newest doc
[ -z "$NEWFILES" ] && NEWFILES=$(ls -t "$QUEUE_DIR"/*.md 2>/dev/null | head -1)
NAMES=$(while IFS= read -r f; do [ -n "$f" ] && basename "$f" .md; done <<< "$NEWFILES")

export FAQIH_NAMES="$NAMES"
export FAQIH_MODE="$HEAD"

python3 - << 'PYEOF'
import json, urllib.request, urllib.parse, sys, os, re

cfg   = json.load(open('/root/config.json'))
token = cfg['telegram_bot_token']
chat  = str(cfg['telegram_chat_id'])
vault = cfg.get('obsidian_vault_name', 'my-brain')
gh    = (cfg.get('github_base', '') or '').rstrip('/')
names = [n for n in os.environ.get('FAQIH_NAMES', '').split('\n') if n.strip()]

if not names:
    sys.exit(0)


def he(s):
    return s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')


def post(payload):
    req = urllib.request.Request(
        f'https://api.telegram.org/bot{token}/sendMessage',
        data=json.dumps(payload).encode(),
        headers={'Content-Type': 'application/json'})
    try:
        urllib.request.urlopen(req, timeout=10)
    except Exception as e:
        print(f'notify error: {e}', file=sys.stderr)


def send_for(name):
    # ── Read the generated plan for a preview ────────────────────────────────
    doc_path = f"/root/knowledge/01-Projects/_queue/{name}.md"
    goal = wiki_ref = plan = ''
    try:
        content = open(doc_path).read()

        def section(text, heading):
            m = re.search(r'## ' + re.escape(heading) + r'\n(.*?)(?=\n## |\Z)', text, re.DOTALL)
            return m.group(1).strip() if m else ''
        goal     = section(content, 'الهدف')[:150]
        wiki_ref = section(content, 'ما تعرفه مسبقاً')[:350]
        plan     = section(content, 'الخطة')[:500]
    except Exception:
        pass

    parts = ['📋 <b>خطة فقيه</b>']
    if goal:
        parts.append(f'\n🎯 <b>الهدف:</b> {he(goal)}')
    if wiki_ref:
        parts.append(f'\n📚 <b>من قبوك:</b>\n{he(wiki_ref)}')
    if plan:
        parts.append(f'\n<b>الخطة:</b>\n{he(plan)}')

    # ── Obsidian deep link — shown as tap-to-copy text, NOT a button ──────────
    # Telegram inline-keyboard url buttons accept only http(s)/tg:// URLs. An
    # obsidian:// button url returns 400 BUTTON_URL_INVALID and drops the WHOLE
    # message. So the deep link lives in the body as <code> (tap-to-copy; opens
    # Obsidian to the exact note); the clickable button uses the GitHub web url.
    obs_file = f"01-Projects/_queue/{name}"
    obs_url  = (f"obsidian://open"
                f"?vault={urllib.parse.quote(vault)}"
                f"&file={urllib.parse.quote(obs_file)}")
    parts.append(f'\n📱 <b>افتح في Obsidian</b> (انسخ الرابط):\n<code>{he(obs_url)}</code>')
    parts.append('\nأو راجع الملاحظة واختر:')
    msg = '\n'.join(parts)

    # ── Inline keyboard ──────────────────────────────────────────────────────
    rows = []
    if gh:
        gh_url = gh + '/' + '/'.join(urllib.parse.quote(p) for p in (obs_file + '.md').split('/'))
        rows.append([{'text': '📄 افتح الملاحظة (GitHub)', 'url': gh_url}])
    rows.append([
        {'text': '✅ اعتمد',       'callback_data': f'idea_approve:{name}'},
        {'text': '🔄 أعد التفكير', 'callback_data': f'idea_rethink:{name}'},
    ])
    rows.append([
        {'text': '⏸ لاحقاً',       'callback_data': f'idea_hold:{name}'},
        {'text': '🗑 تجاهل',        'callback_data': f'idea_discard:{name}'},
    ])

    post({
        'chat_id': chat,
        'text': msg,
        'parse_mode': 'HTML',
        'reply_markup': {'inline_keyboard': rows},
        'disable_web_page_preview': True,
    })


# a header first when فقيه split one message into several plans, so it doesn't look like a glitch
if len(names) > 1:
    post({'chat_id': chat, 'parse_mode': 'HTML',
          'text': f'🧠 استخرج فقيه <b>{len(names)}</b> أفكار من رسالتك — خطة لكل واحدة:'})

for nm in names:
    send_for(nm)
PYEOF
