#!/bin/bash
# Vault organizer — actively restructures the vault with the Fable model (configurable).
# SAFETY: makes a git restore-point commit BEFORE it runs, so the whole pass is one
# command to undo. Never deletes content, never touches raw/ content (read-only there).
# Writes a change summary to AIOS/reports/ and sends it (with the undo command) to Telegram.
#
# Run:  bash /root/vault-organize.sh
# Model override:  VAULT_MODEL=claude-sonnet-5 bash /root/vault-organize.sh
export NVM_DIR=/root/.nvm
export PATH="$HOME/.local/bin:$PATH"
export CLAUDE_CODE_OAUTH_TOKEN=$(tr -d '[:space:]' < /root/.claude-token)
LOG=/root/vault-organize.log
CFG=/root/config.json
MODEL="${VAULT_MODEL:-claude-fable-5}"
cd /root/knowledge || exit 1

DATE=$(date -u +%Y-%m-%d)
mkdir -p AIOS/reports
REPORT="AIOS/reports/${DATE}-vault-organize.md"

TOKEN=$(python3 -c "import json;print(json.load(open('$CFG'))['telegram_bot_token'])")
CHAT=$(python3 -c "import json;print(json.load(open('$CFG'))['telegram_chat_id'])")
GH=$(python3 -c "import json;print(json.load(open('$CFG')).get('github_base',''))" 2>/dev/null)

# ── restore point: commit current state so the whole pass can be undone in one line ──
git add -A >/dev/null 2>&1
git commit -m "restore point before vault-organize ${DATE}" --allow-empty >/dev/null 2>&1
BEFORE=$(git rev-parse HEAD)
echo "$(date -u +%FT%TZ) START vault-organize (model $MODEL, restore point $BEFORE)" >> "$LOG"

TASK="أنت مُنظّم القبو. اقرأ أولاً AIOS/vault-map.md وAIOS/MI.md لتفهم القواعد والبنية المقصودة، ثم نظّم القبو وفقها.

المهام المسموحة (نفّذ الآمن عالي القيمة):
- أصلح الروابط [[المكسورة]]: صحّح الاسم إن كان خطأً إملائياً، أو أنشئ البطاقة الناقصة كجذر مختصر.
- ادمج البطاقات المكرّرة/المتداخلة في بطاقة واحدة، مع **نقل كل المعلومة** وإضافة إشارات إعادة توجيه من الأسماء القديمة.
- أضف frontmatter الناقص وفق قالب vault-map.
- انقل البطاقات اليتيمة إلى مجلدها الصحيح واربطها من index.
- حدّث wiki/index.md ليعكس البنية بعد التنظيم.

قواعد صارمة غير قابلة للتفاوض:
- **لا تحذف أي محتوى إطلاقاً**. الدمج ينقل ولا يفقد. النقل يبقي المعلومة.
- **لا تلمس محتوى raw/** — اقرأ منه فقط، لا تعدّله ولا تنقله.
- عند أي شك في ملف، **اتركه كما هو** وأدرجه في قسم 'يحتاج قرارك' في التقرير بدل تعديله.
- لا تنفّذ أوامر طرفية، لا git، لا حذف ملفات.

في النهاية اكتب تقرير التغييرات في ${REPORT}: قائمة بكل ملف عُدّل/نُقل/دُمج (السطر: ماذا ولماذا)، ثم قسم 'يحتاج قرارك' لما تركته. سجّل سطراً في AIOS/agent-log.md."

OUT=$(timeout 2400 claude -p "$TASK" --model "$MODEL" \
  --allowedTools "Read,Write,Edit,Glob,Grep" --permission-mode acceptEdits 2>&1)
rc=$?
echo "$OUT" >> "$LOG"
echo "$(date -u +%FT%TZ) END vault-organize (rc $rc)" >> "$LOG"

if echo "$OUT" | grep -qiE "session limit|rate limit|usage limit|Not logged in"; then
  curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${CHAT}" \
    --data-urlencode "text=⚠️ تنظيم القبو: حد الجلسة (${MODEL}). لم يُطبَّق شيء يُذكر. أعد المحاولة لاحقاً." >/dev/null
  exit 1
fi

# commit the organizer's changes as one reviewable commit
git add -A >/dev/null 2>&1
git commit -m "vault-organize ${DATE} (model ${MODEL})" >/dev/null 2>&1
AFTER=$(git rev-parse HEAD)
CHANGED=$(git diff --name-only "$BEFORE" "$AFTER" | wc -l | tr -d ' ')

MSG="🗂 تنظيم القبو انتهى (${MODEL}) — ${CHANGED} ملف تغيّر.
التقرير: ${REPORT}"
[ -n "$GH" ] && MSG="${MSG}
${GH}/$(python3 -c "import urllib.parse,sys;print('/'.join(urllib.parse.quote(p) for p in sys.argv[1].split('/')))" "$REPORT")"
MSG="${MSG}

للتراجع عن كل التغييرات:
git -C /root/knowledge reset --hard ${BEFORE}"
curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
  --data-urlencode "chat_id=${CHAT}" --data-urlencode "text=${MSG}" >/dev/null
echo "$(date -u +%FT%TZ) organized: $CHANGED files, undo=$BEFORE" >> "$LOG"
