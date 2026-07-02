#!/bin/bash
# وكيل — project executor. THE most dangerous agent. Hard rules baked in:
#   • Acts on exactly ONE requirements doc with `status: approved`. The gate is never automated.
#   • Builds ONLY under /root/projects/<name> on an isolated git branch. Output = branch + summary.
#   • NEVER deploys, NEVER touches the vault's main, the live services, or anything outside /root/projects.
#   • DRY-RUN by default. Real build requires:  WAKIL_CONFIRM=1 /root/wakil-run.sh
#   • Run MANUALLY only. Not in cron until one clean run is reviewed with Abdullah (CHECKPOINT 7).
export NVM_DIR=/root/.nvm
export PATH="$HOME/.local/bin:$PATH"
export CLAUDE_CODE_OAUTH_TOKEN=$(tr -d '[:space:]' < /root/.claude-token)
VAULT=/root/knowledge
PROJECTS=/root/projects
LOG=/root/wakil.log
QUEUE="$VAULT/01-Projects/_queue"
mkdir -p "$PROJECTS"

# pick ONE approved, not-yet-built doc
DOC=""
for f in "$QUEUE"/*.md; do
  [ -e "$f" ] || continue
  if grep -qiE '^status:\s*approved' "$f" && ! grep -qiE '^status:\s*(built|done)' "$f"; then DOC="$f"; break; fi
done

if [ -z "$DOC" ]; then echo "$(date -u +%FT%TZ) وكيل: no status:approved doc to build — nothing to do." | tee -a "$LOG"; exit 0; fi
NAME=$(basename "$DOC" .md)
echo "$(date -u +%FT%TZ) وكيل: selected approved doc: $NAME" | tee -a "$LOG"

if [ "${WAKIL_CONFIRM:-0}" != "1" ]; then
  echo "DRY-RUN. Would build '$NAME' under $PROJECTS/$NAME on an isolated branch (no deploy)."
  echo "To execute for real: WAKIL_CONFIRM=1 /root/wakil-run.sh"
  exit 0
fi

DEST="$PROJECTS/$NAME"
SPEC=$(cat "$DOC")
TASK="أنت وكيل (اقرأ AIOS/agents/wakil.md أولاً والتزم بحدوده الصارمة). نفّذ مستند المتطلبات التالي (status: approved):

$SPEC

قواعد التنفيذ غير القابلة للتفاوض:
- ابنِ **فقط** داخل $DEST (git init هناك، فرع باسم build/$NAME). لا تكتب خارج هذا المجلد إطلاقاً.
- ممنوع منعاً باتاً: لمس $VAULT (عدا قراءة هذا المستند)، أو الخدمات الحية (docker/systemctl/n8n/nginx)، أو main، أو أي نشر/deploy، أو rm خارج $DEST.
- الناتج: فرع git + commit + ملف PROGRESS.md يلخّص ما بُني وكيف يُراجَع. PR/فرع، لا نشر.
- «منجز» = مسودة أولى عاملة لشيء محدود. اتخذ قرارات معقولة وسجّلها في PROGRESS.md، لا تسألني أثناء البناء.
- عند الانتهاء فقط: حدّث ترويسة $DOC إلى status: built وأضف سطراً في $VAULT/AIOS/agent-log.md.
مشروع واحد فقط."

echo "$(date -u +%FT%TZ) وكيل: BUILD START $NAME" >> "$LOG"
OUT=$(timeout 3000 claude -p "$TASK" --allowedTools "Read,Write,Edit,Glob,Grep,Bash" --permission-mode acceptEdits 2>&1)
rc=$?
echo "$OUT" >> "$LOG"
echo "$(date -u +%FT%TZ) وكيل: BUILD END $NAME (exit $rc)" >> "$LOG"

TOKEN=$(python3 -c "import json;print(json.load(open('/root/config.json'))['telegram_bot_token'])")
CHAT=$(python3 -c "import json;print(json.load(open('/root/config.json'))['telegram_chat_id'])")
if echo "$OUT" | grep -qiE "session limit|rate limit|usage limit|Not logged in"; then
  MSG="⚠️ وكيل: تعذّر بناء «${NAME}» — حد الجلسة. لم يتغيّر status (يبقى approved، سيُحاول الليلة القادمة)."
elif [ $rc -ne 0 ]; then
  MSG="⚠️ وكيل: فشل بناء «${NAME}» (rc ${rc}). راجع /root/wakil.log. لم يُنشر شيء."
else
  MSG="🏗 وكيل: انتهى بناء «${NAME}» في ${DEST} (فرع build/${NAME}). راجع PROGRESS.md — لم يُنشر شيء."
fi
curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" --data-urlencode "chat_id=${CHAT}" --data-urlencode "text=${MSG}" >/dev/null
