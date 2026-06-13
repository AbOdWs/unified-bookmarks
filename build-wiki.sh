#!/bin/bash
# build-wiki runner — مُصنِّف digests new raw/ into wiki/. Used by /rescan and the
# nightly cron (Phase 5). Single-flight via lockfile. Logs to /root/build-wiki.log.
export PATH="$HOME/.local/bin:$PATH"
export CLAUDE_CODE_OAUTH_TOKEN=$(tr -d '[:space:]' < /root/.claude-token)
LOCK=/root/.build-wiki.lock
LOG=/root/build-wiki.log
cd /root/knowledge || exit 1

if [ -e "$LOCK" ] && kill -0 "$(cat "$LOCK" 2>/dev/null)" 2>/dev/null; then
  echo "$(date -u +%FT%TZ) SKIP: build already running (pid $(cat $LOCK))" >> "$LOG"
  exit 0
fi
echo $$ > "$LOCK"
trap 'rm -f "$LOCK"' EXIT

CONTRACT="أنت مُصنِّف. اقرأ AIOS/skills/build-wiki.md أولاً ونفّذ عقده بالكامل على الملفات الجديدة في raw/ (قارن مع AIOS/history/digested.md لمعرفة غير المهضوم). لا تلمس ملفات raw نفسها أبداً. ادمج مع بطاقات wiki الموجودة ولا تكرر. حدّث wiki/index.md و AIOS/history/digested.md و AIOS/agent-log.md. إن لم يوجد raw جديد غير مهضوم فاكتب ذلك وتوقف فوراً."

echo "$(date -u +%FT%TZ) START build-wiki" >> "$LOG"
timeout 2400 claude -p "$CONTRACT" --allowedTools "Read,Write,Edit,Glob,Grep" \
  --permission-mode acceptEdits >> "$LOG" 2>&1
echo "$(date -u +%FT%TZ) END build-wiki (exit $?)" >> "$LOG"
