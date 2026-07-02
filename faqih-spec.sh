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

الفكرة المُقدَّمة:
«$IDEA»

نفّذ بالترتيب الصارم التالي:

الخطوة ١ — ابحث في قبو المعرفة:
استخدم Glob وGrep وRead لتحديد كل بطاقة في wiki/ ذات صلة بهذه الفكرة. لكل بطاقة ذات صلة اكتب: اسمها [[card-name]] + جملة واحدة تشرح الصلة بالفكرة.

الخطوة ٢ — اكتب مستند الخطة في 01-Projects/_queue/<YYYY-MM-DD>-<slug>.md
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

# spec and idea modes: send inline keyboard with action buttons
NEW=$(ls -t 01-Projects/_queue/*.md 2>/dev/null | head -1)
NAME=$(basename "$NEW" .md 2>/dev/null)

export FAQIH_NAME="$NAME"
export FAQIH_MODE="$HEAD"

python3 - << 'PYEOF'
import json, urllib.request, urllib.parse, sys, os, re

cfg   = json.load(open('/root/config.json'))
token = cfg['telegram_bot_token']
chat  = str(cfg['telegram_chat_id'])
vault = cfg.get('obsidian_vault_name', 'my-brain')
name  = os.environ.get('FAQIH_NAME', '')
mode  = os.environ.get('FAQIH_MODE', 'spec')

if not name:
    sys.exit(0)

# ── Read the generated plan for a preview ───────────────────────────────────
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

# ── Build message ────────────────────────────────────────────────────────────
def he(s):
    return s.replace('&','&amp;').replace('<','&lt;').replace('>','&gt;')

parts = ['📋 <b>خطة فقيه</b>']
if goal:
    parts.append(f'\n🎯 <b>الهدف:</b> {he(goal)}')
if wiki_ref:
    parts.append(f'\n📚 <b>من قبوك:</b>\n{he(wiki_ref)}')
if plan:
    parts.append(f'\n<b>الخطة:</b>\n{he(plan)}')
parts.append('\nاختر أو راجع التفاصيل في Obsidian:')
msg = '\n'.join(parts)

# ── Obsidian deep link ───────────────────────────────────────────────────────
obs_file = f"01-Projects/_queue/{name}"
obs_url  = (f"obsidian://open"
            f"?vault={urllib.parse.quote(vault)}"
            f"&file={urllib.parse.quote(obs_file)}")

# ── Inline keyboard ──────────────────────────────────────────────────────────
keyboard = {
    'inline_keyboard': [
        [{'text': '📱 فتح في Obsidian', 'url': obs_url}],
        [
            {'text': '✅ اعتمد',        'callback_data': f'idea_approve:{name}'},
            {'text': '🔄 أعد التفكير',  'callback_data': f'idea_rethink:{name}'},
            {'text': '⏸ لاحقاً',        'callback_data': f'idea_hold:{name}'},
            {'text': '🗑 تجاهل',         'callback_data': f'idea_discard:{name}'},
        ]
    ]
}

body = json.dumps({
    'chat_id': chat,
    'text': msg,
    'parse_mode': 'HTML',
    'reply_markup': keyboard,
    'disable_web_page_preview': True,
}).encode()

req = urllib.request.Request(
    f'https://api.telegram.org/bot{token}/sendMessage',
    data=body,
    headers={'Content-Type': 'application/json'},
)
try:
    urllib.request.urlopen(req, timeout=10)
except Exception as e:
    print(f'notify error: {e}', file=sys.stderr)
PYEOF
