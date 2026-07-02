#!/bin/bash
# فقيه — researcher/planner. Turns an idea into a requirements DRAFT in 01-Projects/_queue/.
# فقيه plans, never executes. Output is what Abdullah signs off (status: draft -> he sets approved).
export NVM_DIR=/root/.nvm
export PATH="$HOME/.local/bin:$PATH"
export CLAUDE_CODE_OAUTH_TOKEN=$(tr -d '[:space:]' < /root/.claude-token)
LOG=/root/faqih.log
cd /root/knowledge || exit 1
MODE="${1:-spec}"            # spec | research
IDEA=$(cat /root/.faqih-request.txt 2>/dev/null)
[ -z "$IDEA" ] && exit 0

TOKEN=$(python3 -c "import json;print(json.load(open('/root/config.json'))['telegram_bot_token'])")
CHAT=$(python3 -c "import json;print(json.load(open('/root/config.json'))['telegram_chat_id'])")

if [ "$MODE" = "research" ]; then
  TASK="أنت فقيه (اقرأ AIOS/agents/faqih.md أولاً). سؤال البحث: «$IDEA». اكتب تقريراً في wiki/synthesis/<تاريخ>-<slug>.md بقالب تقريرك: السؤال / الخيارات / المقايضات / قيودي (ميزانية، منطقة، بنيتي الحالية إن عُرفت) / التوصية / درجة الثقة وما تجهله / المصادر. اعرض المقايضات لا الأحكام، وصرّح بما لا تعرفه. لا تنفّذ شيئاً. سجّل في AIOS/agent-log.md. لا تلمس raw."
  HEAD="🔎 *فقيه* — تقرير بحث جاهز"
else
  TASK="أنت فقيه (اقرأ AIOS/agents/faqih.md أولاً). الفكرة: «$IDEA». حوّلها إلى **مستند متطلبات** في 01-Projects/_queue/<تاريخ>-<slug>.md بترويسة فيها 'status: draft' و 'agent: فقيه'، وبقالب المتطلبات: الهدف بجملة / السياق / داخل النطاق / **خارج النطاق صراحة** / الوكلاء الفرعيون المطلوبون / الخطوات / تعريف «نسخة أولى منجزة» / المخاطر. فقيه **يخطط ولا ينفّذ أبداً** — هذا المستند هو ما يوقّع عليه عبدالله. لا تلمس raw. سجّل في AIOS/agent-log.md."
  HEAD="📋 *فقيه* — مسودة متطلبات جاهزة"
fi

echo "$(date -u +%FT%TZ) START faqih $MODE: $IDEA" >> "$LOG"
OUT=$(timeout 900 claude -p "$TASK" --allowedTools "Read,Write,Edit,Glob,Grep,WebSearch,WebFetch" --permission-mode acceptEdits 2>&1)
echo "$OUT" >> "$LOG"
echo "$(date -u +%FT%TZ) END faqih $MODE" >> "$LOG"

# find the newest file faqih just wrote and notify
if [ "$MODE" = "research" ]; then NEW=$(ls -t wiki/synthesis/*.md 2>/dev/null | head -1); else NEW=$(ls -t 01-Projects/_queue/*.md 2>/dev/null | head -1); fi
NAME=$(basename "$NEW" .md 2>/dev/null)
MSG="${HEAD}: ${NAME}"
[ "$MODE" = "spec" ] && MSG="${MSG}

راجعها في Obsidian. للموافقة على التنفيذ: غيّر status إلى approved في ترويسة الملف (هذه بوابتك — وكيل لا ينفّذ إلا المعتمد)."
curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" --data-urlencode "chat_id=${CHAT}" --data-urlencode "text=${MSG}" -d "parse_mode=Markdown" >/dev/null
