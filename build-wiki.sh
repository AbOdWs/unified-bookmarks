#!/bin/bash
# build-wiki runner — مُصنِّف digests new raw/ into wiki/. Used by /rescan and the
# nightly cron. Single-flight via lockfile. Retries on Claude session/rate limits.
export PATH="$HOME/.local/bin:$PATH"
export CLAUDE_CODE_OAUTH_TOKEN=$(tr -d '[:space:]' < /root/.claude-token)
LOCK=/root/.build-wiki.lock
LOG=/root/build-wiki.log
MAX_ATTEMPTS=8          # ~ up to 4h of retries at 30m each
RETRY_SLEEP=1800
cd /root/knowledge || exit 1

if [ -e "$LOCK" ] && kill -0 "$(cat "$LOCK" 2>/dev/null)" 2>/dev/null; then
  echo "$(date -u +%FT%TZ) SKIP: build already running (pid $(cat $LOCK))" >> "$LOG"
  exit 0
fi
echo $$ > "$LOCK"
trap 'rm -f "$LOCK"' EXIT

CONTRACT="أنت مُصنِّف. اقرأ AIOS/skills/build-wiki.md أولاً ونفّذ عقده بالكامل على الملفات الجديدة في raw/ (قارن مع AIOS/history/digested.md لمعرفة غير المهضوم — ركّز على raw/inbox). لا تلمس ملفات raw نفسها أبداً. ادمج مع بطاقات wiki الموجودة ولا تكرر. حدّث wiki/index.md و AIOS/history/digested.md و AIOS/agent-log.md، وسجّل كل ملف raw/inbox هضمته في digested.md. إن لم يوجد raw جديد غير مهضوم فاكتب 'NO-NEW-RAW' وتوقف فوراً."

attempt=1
while [ $attempt -le $MAX_ATTEMPTS ]; do
  echo "$(date -u +%FT%TZ) START build-wiki (attempt $attempt)" >> "$LOG"
  OUT=$(timeout 2400 claude -p "$CONTRACT" --allowedTools "Read,Write,Edit,Glob,Grep" \
    --permission-mode acceptEdits 2>&1)
  rc=$?
  echo "$OUT" >> "$LOG"
  echo "$(date -u +%FT%TZ) END build-wiki (rc $rc, attempt $attempt)" >> "$LOG"
  if echo "$OUT" | grep -qiE "session limit|rate limit|usage limit|Not logged in"; then
    echo "$(date -u +%FT%TZ) LIMIT hit — sleeping ${RETRY_SLEEP}s then retrying" >> "$LOG"
    sleep $RETRY_SLEEP
    attempt=$((attempt+1))
    continue
  fi
  # real completion (work done or nothing-to-do)
  exit 0
done
echo "$(date -u +%FT%TZ) GAVE UP build-wiki after $MAX_ATTEMPTS attempts" >> "$LOG"
# failure alert to owner (the report's quick-win #1)
TOKEN=$(python3 -c "import json;print(json.load(open('/root/config.json'))['telegram_bot_token'])" 2>/dev/null)
CHAT=$(python3 -c "import json;print(json.load(open('/root/config.json'))['telegram_chat_id'])" 2>/dev/null)
[ -n "$TOKEN" ] && curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" --data-urlencode "chat_id=${CHAT}" --data-urlencode "text=⚠️ بناء الويكي (مُصنِّف) فشل بعد ${MAX_ATTEMPTS} محاولات الليلة (حد الجلسة غالباً). الويكي لم يتحدّث — جرّب /rescan لاحقاً." >/dev/null
exit 1
