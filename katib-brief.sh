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

# health check (morning only) — surface any broken AIOS component (report item 5)
HEALTH=""
if [ "$KIND" = "morning" ]; then
  probs=""
  for svc in build-trigger-api ytdlp-api whisper-api; do
    systemctl is-active --quiet "$svc.service" || probs="${probs}\n• خدمة ${svc} متوقفة"
  done
  last=$(grep -E "GAVE UP|rc [1-9]" /root/build-wiki.log 2>/dev/null | tail -1)
  [ -n "$last" ] && probs="${probs}\n• آخر بناء ويكي به مشكلة: ${last}"
  curl -s --max-time 5 http://localhost:8767/ >/dev/null 2>&1 || probs="${probs}\n• build-trigger لا يستجيب"
  [ -n "$probs" ] && HEALTH="\n\n <b>صحة النظام:</b>${probs}"
fi

# deliver to Telegram as HTML (file stays clean Markdown for Obsidian; we convert on send)
if [ -f "$OUT" ]; then
  TOKEN=$(python3 -c "import json;print(json.load(open('/root/config.json'))['telegram_bot_token'])")
  CHAT=$(python3 -c "import json;print(json.load(open('/root/config.json'))['telegram_chat_id'])")
  HEAD=$([ "$KIND" = "morning" ] && echo " <b>موجز الصباح</b>" || echo " <b>ختام المساء</b>")
  # strip YAML frontmatter, HTML-escape, **bold**->-<b>, drop leading # from headings
  BODY=$(perl -0777 -pe 's/^---\n.*?\n---\n//s' "$OUT" \
    | perl -pe 's/&/&amp;/g; s/</&lt;/g; s/>/&gt;/g' \
    | perl -pe 's/\*\*(.+?)\*\*/<b>$1<\/b>/g; s/^#+\s*(.+)$/<b>$1<\/b>/' )
  curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${CHAT}" \
    --data-urlencode "text=${HEAD} — ${TODAY}

${BODY}$(printf "$HEALTH")" \
    -d "parse_mode=HTML" -d "disable_web_page_preview=true" >/dev/null
  echo "$(date -u +%FT%TZ) sent $KIND to telegram" >> "$LOG"
fi
