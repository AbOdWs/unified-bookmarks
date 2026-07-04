#!/bin/bash
# Vault connector — READ-ONLY. Fable reads the vault and SUGGESTS new links between
# existing cards + emergent ideas from combining notes. It has only Read/Glob/Grep
# (no Write), so it changes nothing — it only writes a suggestions report (captured from
# its output) to AIOS/reports/<date>-vault-connections.md and pings Telegram.
#
# Run:  bash /root/vault-connect.sh
# Model override:  VAULT_MODEL=claude-sonnet-5 bash /root/vault-connect.sh
export NVM_DIR=/root/.nvm
export PATH="$HOME/.local/bin:$PATH"
export CLAUDE_CODE_OAUTH_TOKEN=$(tr -d '[:space:]' < /root/.claude-token)
LOG=/root/vault-connect.log
CFG=/root/config.json
MODEL="${VAULT_MODEL:-claude-fable-5}"
cd /root/knowledge || exit 1

DATE=$(date -u +%Y-%m-%d)
mkdir -p AIOS/reports
REPORT="AIOS/reports/${DATE}-vault-connections.md"

# literal heredoc: no backtick/pipe/$ inside the prompt is ever run by the shell
IFS= read -r -d '' TASK <<'TASKEOF'
أنت رسّام خرائط المعرفة. مهمتك اكتشاف *روابط جديدة* و*أفكار ناشئة* في القبو — لا تعديل، لا كتابة ملفات.
اقرأ بطاقات wiki/ (concepts وsynthesis وentities وأهم sources) واستخدم Grep/Read للتحقق.

أخرِج تقريراً بصيغة Markdown بهذه الأقسام:

## 1. روابط مقترحة (بين بطاقتين قائمتين غير مرتبطتين حالياً)
لكل اقتراح، والأعلى قيمة أولاً:
- [[البطاقة-أ]] ↔ [[البطاقة-ب]]
- نوع الصلة (مثال: نفس الأداة، مفهوم يفسّر الآخر، تطبيق عملي لفكرة نظرية…).
- سبب الصلة في جملة واحدة.
- شاهد: اقتبس مقطعاً قصيراً من كل بطاقة يثبت الصلة.
- ثقة: عالية/متوسطة.

## 2. أفكار ناشئة (من دمج بطاقتين أو ثلاث)
لكل فكرة:
- البطاقات المصدر: [[..]] + [[..]] (+[[..]]).
- الفكرة/البصيرة الجديدة التي تتولّد من جمعها (جملتان).
- الإجراء المقترح: بطاقة تركيب جديدة؟ مشروع؟ فكرة تُرسل لفقيه عبر /idea؟

## 3. بطاقات محورية وفجوات
- أكثر 3 بطاقات ترشّح لأن تصبح مركز عنقود (hub).
- فجوة أو فجوتان: موضوع تتكرر إشاراته لكن لا بطاقة مفهوم تجمعه.

قواعد صارمة لمنع الاختراع:
- لا تقترح رابطاً إلا بعد التأكد بـ Grep أن **كلتا** البطاقتين موجودتان فعلاً كملف في wiki/. لا تخترع أسماء بطاقات.
- تأكّد أن الرابط **غير موجود أصلاً** (البطاقة أ لا تشير بالفعل إلى ب).
- إن لم تجد شاهداً نصياً حقيقياً للصلة، لا تُدرجها.
- رتّب بالقيمة، وحدّد عدد الاقتراحات بما هو حقيقي فقط (جودة لا كمية).

أخرِج التقرير كنص كامل فقط (سيُحفظ تلقائياً). لا تكتب أي ملف.
TASKEOF

echo "$(date -u +%FT%TZ) START vault-connect (model $MODEL)" >> "$LOG"
OUT=$(timeout 1800 claude -p "$TASK" --model "$MODEL" --allowedTools "Read,Glob,Grep" 2>&1)
rc=$?
echo "$(date -u +%FT%TZ) END vault-connect (rc $rc)" >> "$LOG"

TOKEN=$(python3 -c "import json;print(json.load(open('$CFG'))['telegram_bot_token'])")
CHAT=$(python3 -c "import json;print(json.load(open('$CFG'))['telegram_chat_id'])")
GH=$(python3 -c "import json;print(json.load(open('$CFG')).get('github_base',''))" 2>/dev/null)

if echo "$OUT" | grep -qiE "session limit|rate limit|usage limit|Not logged in"; then
  echo "$OUT" >> "$LOG"
  curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${CHAT}" \
    --data-urlencode "text=⚠️ ربط القبو: حد الجلسة (${MODEL}). أعد المحاولة بعد التصفير." >/dev/null
  exit 1
fi

{
  echo "---"
  echo "title: روابط وأفكار مقترحة ${DATE}"
  echo "type: report"
  echo "agent: راسم-الخرائط"
  echo "date: ${DATE}"
  echo "---"
  echo
  printf '%s\n' "$OUT"
} > "$REPORT"

MSG="🔗 اقتراحات الروابط والأفكار جاهزة (${DATE}).
افتحها في Obsidian: ${REPORT}"
[ -n "$GH" ] && MSG="${MSG}
${GH}/$(python3 -c "import urllib.parse,sys;print('/'.join(urllib.parse.quote(p) for p in sys.argv[1].split('/')))" "$REPORT")"
curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
  --data-urlencode "chat_id=${CHAT}" --data-urlencode "text=${MSG}" >/dev/null
echo "$(date -u +%FT%TZ) report saved: $REPORT" >> "$LOG"
echo "DONE -> $REPORT"
