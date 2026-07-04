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
# فقيه made NO new plan (a duplicate, a blocker like an unreadable link, a needs-info
# case, or it edited an existing draft). Relay its ACTUAL message — never re-send the
# newest card (that old fallback made a 2nd idea show the 1st idea's plan). This also
# means a rate-limit ("session limit · resets …") now reaches you instead of silence.
if [ -z "$NEWFILES" ]; then
  RELAY=$(printf '%s' "$OUT" | tail -c 3500)
  curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${CHAT}" \
    --data-urlencode "text=📋 فقيه:
${RELAY}" >/dev/null
  exit 0
fi
NAMES=$(while IFS= read -r f; do [ -n "$f" ] && basename "$f" .md; done <<< "$NEWFILES")

# header first when فقيه split one message into several plans, so it doesn't look like a glitch
COUNT=$(printf '%s\n' "$NAMES" | sed '/^$/d' | wc -l | tr -d ' ')
if [ "$COUNT" -gt 1 ]; then
  curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${CHAT}" \
    --data-urlencode "text=🧠 استخرج فقيه ${COUNT} أفكار من رسالتك — خطة لكل واحدة:" >/dev/null
fi

# one card per new plan; plan-notify.py assigns a stable #code and builds the buttons
while IFS= read -r nm; do
  [ -n "$nm" ] && NAME="$nm" python3 /root/plan-notify.py
done <<< "$NAMES"
