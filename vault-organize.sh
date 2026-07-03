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

# NOTE: single-quoted heredoc delimiter ('TASKEOF') = fully literal. No shell will try to
# run the backticks, |, $ or [[..]] inside the prompt. {{REPORT}} is substituted after.
IFS= read -r -d '' TASK <<'TASKEOF'
أنت مُنظّم القبو. اقرأ أولاً أحدث تقرير تدقيق (أعلى ملف في AIOS/reports/ ينتهي بـ vault-audit.md) وكذلك AIOS/vault-map.md وAIOS/MI.md. نفّذ فقط الإصلاحات الآمنة عالية القيمة التالية، ولا تتجاوزها إطلاقاً:

(أ) الروابط المكسورة:
- صحّح [[bروتوكول-MCP]] إلى [[بروتوكول-MCP]] (حرف b لاتيني بالخطأ).
- صحّح [[توكيل-دورر]] إلى [[تيم-دورر]].
- أنشئ بطاقة wiki/concepts/مكتبات-مهارات-Claude.md (مطلوبة من ملفين) بترويسة صحيحة ومحتوى جذر مختصر يشرح المفهوم.
- حوّل وصلات العناصر الداخلية إلى نص عادي (ليست بطاقات): [[GoSearch]]، [[monokern]]، [[NineRouter]]، [[running codex locally with ollama]]، [[دليل تسوق قوانزو]]، [[دانيال-سان]].
- في wiki/entities/obsidian.md حوّل [[wikilinks]] إلى نص عادي (مصطلح توضيحي).

(ب) تقليم wiki/index.md: انقل موجزات البناءات المتراكمة في رأسه إلى ملف جديد AIOS/history/index-build-archive.md، وأبقِ في index.md موجز آخر build فقط + الفهرس. نقل لا حذف — لا تُفقد أي معلومة.

(ج) ربط البطاقتين غير المرئيتين: أضف hermes-agent-ecosystem-research و simon-says-ai-second-brain-youtube إلى wiki/index.md، وأضف وصلة إليهما من أقرب بطاقة أم.

(د) توثيق الوكلاء: أضف abodlinks و travelrepost و dev-research إلى جدول الفريق في AIOS/MI.md. ووحّد صيغة AIOS/agent-log.md على النمط العربي المفصول بالخط العمودي.

(هـ) إصلاح صغير: أضف (agent: الساعي) + تاريخ لقالب النشر في AIOS/skills/courier.md لملفات _public/ القادمة.

لا تفعل الآتي — اتركه لقرار المالك وأدرجه في قسم 'يحتاج قرارك': دمج بطاقات placeholder الثلاث، دمج/تخصيص العناقيد المتداخلة (الدخل الرقمي، الاستضافة الذاتية، عنقود tomdoerr)، حذف أي ملف بما فيه ملفات .bak، تغيير قيمة status الى built.

قواعد صارمة غير قابلة للتفاوض:
- لا تحذف أي محتوى إطلاقاً. كل عملية نقل تُبقي المعلومة.
- لا تلمس محتوى raw/ — اقرأ فقط.
- عند أي شك، اترك الملف وأدرجه في 'يحتاج قرارك'.
- لا تنفّذ أوامر طرفية، لا git.

في النهاية اكتب تقرير التغييرات في {{REPORT}}: قائمة بكل ملف عُدّل (السطر: ماذا ولماذا)، ثم قسم 'يحتاج قرارك' لما تركته عمداً. سجّل سطراً في AIOS/agent-log.md.
TASKEOF
TASK=${TASK//\{\{REPORT\}\}/$REPORT}

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
