#!/bin/bash
# الساعي — courier. Sanitize wiki cards marked `share: public` into _public/_pending/
# (awaiting Abdullah's approval), then Telegram each preview for ✅/❌.
export PATH="$HOME/.local/bin:$PATH"
export CLAUDE_CODE_OAUTH_TOKEN=$(tr -d '[:space:]' < /root/.claude-token)
LOCK=/root/.courier.lock
LOG=/root/courier.log
cd /root/knowledge || exit 1

if [ -e "$LOCK" ] && kill -0 "$(cat "$LOCK" 2>/dev/null)" 2>/dev/null; then exit 0; fi
echo $$ > "$LOCK"; trap 'rm -f "$LOCK"' EXIT
mkdir -p _public/_pending

TASK="أنت تنفّذ مهارة الساعي (اقرأ AIOS/skills/courier.md أولاً والتزم بها حرفياً). افحص كل بطاقات wiki/ وابحث عن التي تحمل في ترويستها 'share: public' وليس لها نسخة في _public/ ولا في _public/_pending/. لكل بطاقة كهذه: (١) أنشئ نسخة معقّمة — احذف كل معلومة شخصية (أسماء خاصة، أماكن إقامة، أرقام، ماليات، صحة، علاقات، خطط خاصة)، واستبدل كل [[رابط لبطاقة خاصة]] بملخص معقّم بسطر أو احذفه، واحذف الترويسة الداخلية واترك العنوان والمحتوى العام فقط. (٢) اكتب النسخة المعقّمة في _public/_pending/<اسم-البطاقة>.md. **لا تكتب في _public/ مباشرة** — الموافقة لعبدالله. قاعدة الفشل الآمن: إن شككت أن معلومةً ليست عامة فاحذفها. (٣) في النهاية اكتب أسماء البطاقات التي عقّمتها (اسم لكل سطر، بلا امتداد) في _public/_pending/_manifest.txt (أضف للموجود، لا تكرر). إن لم توجد بطاقات share: public جديدة فاكتب 'NONE' وتوقف. سجّل فعلك في AIOS/agent-log.md. لا تلمس raw."

echo "$(date -u +%FT%TZ) START courier" >> "$LOG"
timeout 900 claude -p "$TASK" --allowedTools "Read,Write,Edit,Glob,Grep" --permission-mode acceptEdits >> "$LOG" 2>&1
echo "$(date -u +%FT%TZ) END courier (exit $?)" >> "$LOG"

# Telegram a preview of each freshly-staged pending card
TOKEN=$(python3 -c "import json;print(json.load(open('/root/config.json'))['telegram_bot_token'])")
CHAT=$(python3 -c "import json;print(json.load(open('/root/config.json'))['telegram_chat_id'])")
sent_any=0
for f in _public/_pending/*.md; do
  [ -e "$f" ] || continue
  name=$(basename "$f" .md)
  # HTML-escape the card preview and collapse it into an expandable blockquote
  preview=$(head -c 1500 "$f" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g')
  curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${CHAT}" \
    --data-urlencode "text=📤 <b>الساعي</b> — جاهز للنشر: ${name}
<blockquote expandable>${preview}</blockquote>
وافق: /approve ${name}
ارفض: /reject ${name}" \
    -d "parse_mode=HTML" -d "disable_web_page_preview=true" >/dev/null
  sent_any=1
done
[ $sent_any -eq 0 ] && curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" --data-urlencode "chat_id=${CHAT}" --data-urlencode "text=ℹ️ الساعي: لا بطاقات جديدة معلّمة share: public." >/dev/null
echo "$(date -u +%FT%TZ) courier delivered (sent_any=$sent_any)" >> "$LOG"
