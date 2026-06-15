#!/bin/bash
# الساعي — courier. Sanitizes wiki cards into _public/_pending/ (awaiting AbOd's approval),
# then Telegram each preview. Two modes:
#   no arg / no topic file  → only cards marked `share: public`
#   topic given             → all cards relevant to that topic
# Every published card gets `public-topics: [<topic>]` so guests see only their invited topics.
export HOME=/root; export PATH="/root/.local/bin:$PATH"
export CLAUDE_CODE_OAUTH_TOKEN=$(tr -d '[:space:]' < /root/.claude-token)
LOCK=/root/.courier.lock
LOG=/root/courier.log
cd /root/knowledge || exit 1
TOPIC=$(cat /root/.courier-topic.txt 2>/dev/null); : > /root/.courier-topic.txt

if [ -e "$LOCK" ] && kill -0 "$(cat "$LOCK" 2>/dev/null)" 2>/dev/null; then exit 0; fi
echo $$ > "$LOCK"; trap 'rm -f "$LOCK"' EXIT
mkdir -p _public/_pending

VALUES="التزم بقيم المالك (اقرأ AIOS/owner-profile.md): صدق ووضوح، **عدم جمع أو كشف أي معلومة شخصية**، والتوافق مع القيم الإسلامية والسعودية. قاعدة الفشل الآمن: إن شككت أن معلومةً ليست عامة فاحذفها."

if [ -n "$TOPIC" ]; then
  SCOPE="ابحث في كل بطاقات wiki/ عن المتعلقة بموضوع «$TOPIC» (بالوسوم أو المجال أو المحتوى)، وأيضاً أي بطاقة عليها share: public وليست منشورة بعد. لكل واحدة أضف في ترويسة النسخة المعقّمة: public-topics: [$TOPIC]."
else
  SCOPE="ابحث عن البطاقات التي تحمل share: public وليس لها نسخة في _public/ ولا _public/_pending/. لكل واحدة استنتج موضوعاً عاماً مناسباً وضعه: public-topics: [<الموضوع>]."
fi

TASK="أنت تنفّذ مهارة الساعي (اقرأ AIOS/skills/courier.md أولاً). $SCOPE
لكل بطاقة: (١) أنشئ نسخة معقّمة — احذف كل معلومة شخصية (أسماء خاصة، أماكن إقامة، أرقام، ماليات، صحة، علاقات، خطط خاصة)، واستبدل روابط البطاقات الخاصة بملخص معقّم بسطر أو احذفها، واترك العنوان والمحتوى العام فقط مع ترويسة فيها public-topics. (٢) اكتب النسخة في _public/_pending/<اسم-البطاقة>.md. **لا تكتب في _public/ مباشرة** — الموافقة للمالك. (٣) اكتب أسماء ما عقّمته (اسم لكل سطر) في _public/_pending/_manifest.txt. إن لم توجد بطاقات مناسبة فاكتب 'NONE' وتوقف. $VALUES سجّل فعلك في AIOS/agent-log.md. لا تلمس raw. لا تستخدم إيموجي."

echo "$(date -u +%FT%TZ) START courier (topic='$TOPIC')" >> "$LOG"
timeout 1200 claude -p "$TASK" --allowedTools "Read,Write,Edit,Glob,Grep" --permission-mode acceptEdits >> "$LOG" 2>&1
echo "$(date -u +%FT%TZ) END courier (exit $?)" >> "$LOG"

TOKEN=$(python3 -c "import json;print(json.load(open('/root/config.json'))['telegram_bot_token'])")
CHAT=$(python3 -c "import json;print(json.load(open('/root/config.json'))['telegram_chat_id'])")
sent_any=0
for f in _public/_pending/*.md; do
  [ -e "$f" ] || continue
  name=$(basename "$f" .md)
  preview=$(head -c 1500 "$f" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g')
  curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${CHAT}" \
    --data-urlencode "text=الساعي — جاهز للنشر: ${name}
<blockquote expandable>${preview}</blockquote>
وافق: /approve ${name}    (أو /approve all)
ارفض: /reject ${name}" \
    -d "parse_mode=HTML" -d "disable_web_page_preview=true" >/dev/null
  sent_any=1
done
if [ $sent_any -eq 0 ]; then
  msg="الساعي: لا بطاقات جديدة للنشر"; [ -n "$TOPIC" ] && msg="الساعي: لم أجد بطاقات مناسبة لموضوع «$TOPIC»"
  curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" --data-urlencode "chat_id=${CHAT}" --data-urlencode "text=${msg}" >/dev/null
fi
echo "$(date -u +%FT%TZ) courier delivered (sent_any=$sent_any)" >> "$LOG"
