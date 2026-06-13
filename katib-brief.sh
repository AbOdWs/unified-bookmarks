#!/bin/bash
# كاتب — أمين السر. morning|evening brief → _briefs/ then push to Telegram.
# Usage: katib-brief.sh morning|evening
export PATH="$HOME/.local/bin:$PATH"
export CLAUDE_CODE_OAUTH_TOKEN=$(tr -d '[:space:]' < /root/.claude-token)
KIND="${1:-morning}"
LOG=/root/katib.log
cd /root/knowledge || exit 1

# Saudi date (UTC+3) for the filename/heading
TODAY=$(TZ='Asia/Riyadh' date +%F)
OUT="_briefs/${TODAY}-${KIND}.md"

if [ "$KIND" = "morning" ]; then
  TASK="اكتب *موجز الصباح* ليوم ${TODAY}. أنت كاتب (راجع AIOS/agents/katib.md). اقرأ AIOS/tasks.md (المصدر الموحّد للمهام والتذكيرات والتقويم) وابرز: المتأخر، وما يستحق اليوم ${TODAY}، والقادم خلال ٧ أيام. ثم افحص wiki/index.md (نشط هذا الأسبوع + خيوط مفتوحة) وعُدّ عناصر raw/inbox غير المهضومة. اكتب الملف ${OUT} بصيغة Markdown: سطر عنوان ثم **ثلاثة أسطر كحدّ أقصى** تقول ((ما المهم اليوم)) — أولوية للمهام/المواعيد المستحقة. مختصر واستباقي. لا تلمس raw."
else
  TASK="اكتب *ختام المساء* ليوم ${TODAY}. أنت كاتب (راجع AIOS/agents/katib.md). (أ) افحص raw/inbox وراء أي *تذكير* جديد (سطر **Reminder:** بتاريخ) الْتُقط اليوم ولم يُسجَّل بعد في AIOS/tasks.md، وأضِفه إلى قسم التذكيرات في tasks.md. (ب) لخّص ما الْتُقط اليوم وما تبقّى معلّقاً. اكتب الملف ${OUT}: سطر عنوان ثم **ثلاثة أسطر كحدّ أقصى**. حدّث updated في ترويسة tasks.md إن عدّلته. مختصر. لا تلمس raw."
fi

echo "$(date -u +%FT%TZ) START katib $KIND" >> "$LOG"
timeout 600 claude -p "$TASK" --allowedTools "Read,Write,Edit,Glob,Grep" \
  --permission-mode acceptEdits >> "$LOG" 2>&1
echo "$(date -u +%FT%TZ) END katib $KIND (exit $?)" >> "$LOG"

# deliver to Telegram
if [ -f "$OUT" ]; then
  TOKEN=$(python3 -c "import json;print(json.load(open('/root/config.json'))['telegram_bot_token'])")
  CHAT=$(python3 -c "import json;print(json.load(open('/root/config.json'))['telegram_chat_id'])")
  HEAD=$([ "$KIND" = "morning" ] && echo "🌅 موجز الصباح" || echo "🌙 ختام المساء")
  BODY=$(cat "$OUT")
  curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${CHAT}" \
    --data-urlencode "text=${HEAD} — ${TODAY}

${BODY}" \
    -d "parse_mode=Markdown" >/dev/null
  echo "$(date -u +%FT%TZ) sent $KIND to telegram" >> "$LOG"
fi
