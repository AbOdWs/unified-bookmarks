#!/bin/bash
# Vault auditor — READ-ONLY analysis of the whole knowledge vault.
# It runs Claude with only Read/Glob/Grep (NO Write tool), so it physically cannot edit
# a single note. The report is captured from the model's output and saved by THIS script
# to AIOS/reports/<date>-vault-audit.md, then a summary is sent to Telegram.
#
# Run:  bash /root/vault-audit.sh
# Cron (weekly, optional):  0 6 * * 0  /bin/bash /root/vault-audit.sh
export NVM_DIR=/root/.nvm
export PATH="$HOME/.local/bin:$PATH"
export CLAUDE_CODE_OAUTH_TOKEN=$(tr -d '[:space:]' < /root/.claude-token)
LOG=/root/vault-audit.log
CFG=/root/config.json
cd /root/knowledge || exit 1

DATE=$(date -u +%Y-%m-%d)
mkdir -p AIOS/reports
REPORT="AIOS/reports/${DATE}-vault-audit.md"

TASK="أنت مدقّق القبو (vault auditor). مهمتك تحليل القبو فقط — لا تملك أدوات كتابة، فلن تعدّل أي ملاحظة.
اقرأ أولاً AIOS/vault-map.md وAIOS/MI.md إن وُجدا لتفهم القواعد والبنية المقصودة.
استخدم Glob وGrep بكثافة للفحص البنيوي (العدّ، الروابط، الأيتام) ولا تقرأ كل ملف بالكامل — اقرأ فقط الملفات المشبوهة أو العيّنات. القبو قد يكون كبيراً، فكن اقتصادياً.

أخرِج تقريراً كاملاً بصيغة Markdown (سيُحفظ تلقائياً — لا تحتاج لكتابته بنفسك) يغطّي بهذا الترتيب:

# تدقيق القبو — ${DATE}

## 1. نظرة عامة
عدد الملفات في كل مجلد رئيسي (raw, wiki, 01-Projects, _public, AIOS...).

## 2. ملاحظات يتيمة
بطاقات في wiki/ لا يشير إليها شيء ولا تشير هي لشيء عبر [[...]].

## 3. روابط مكسورة
[[وصلات]] تشير إلى ملفات غير موجودة (مع اسم الملف المصدر).

## 4. تكرار وتداخل
موضوعات مكرّرة أو بطاقات مرشّحة للدمج.

## 5. بطاقات ضعيفة
ملفات قصيرة جداً أو مجرد عنوان بلا محتوى فعلي.

## 6. خام غير مهضوم
عناصر في raw/ مضى عليها وقت ولم تُبنَ بطاقات منها (قارن مع AIOS/history/digested.md إن وُجد).

## 7. ترويسات ومعايير
ملفات بلا frontmatter صحيح أو خارجة عن قواعد vault-map.

## 8. التوصيات (مرتّبة بالأولوية)
أعلى قيمة أولاً. لكل توصية: ماذا / لماذا / كيف — وحجم الأثر (كبير/متوسط/صغير).

اجعله عملياً وموجزاً ومحدداً (اذكر أسماء ملفات فعلية، لا كلاماً عاماً). لا تقترح تنفيذاً الآن — التقرير فقط."

echo "$(date -u +%FT%TZ) START vault-audit" >> "$LOG"
OUT=$(timeout 1800 claude -p "$TASK" --allowedTools "Read,Glob,Grep" 2>&1)
rc=$?
echo "$(date -u +%FT%TZ) END vault-audit (rc $rc)" >> "$LOG"

TOKEN=$(python3 -c "import json;print(json.load(open('$CFG'))['telegram_bot_token'])")
CHAT=$(python3 -c "import json;print(json.load(open('$CFG'))['telegram_chat_id'])")
GH=$(python3 -c "import json;print(json.load(open('$CFG')).get('github_base',''))" 2>/dev/null)

# guard: only save if the model actually produced a report (not a session/rate-limit message)
if echo "$OUT" | grep -qiE "session limit|rate limit|usage limit|Not logged in"; then
  echo "$OUT" >> "$LOG"
  curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${CHAT}" \
    --data-urlencode "text=⚠️ تدقيق القبو: حد الجلسة. أعد المحاولة لاحقاً." >/dev/null
  exit 1
fi

# save the report (front-matter + the model's markdown output)
{
  echo "---"
  echo "title: تدقيق القبو ${DATE}"
  echo "type: report"
  echo "agent: مدقق-القبو"
  echo "date: ${DATE}"
  echo "---"
  echo
  printf '%s\n' "$OUT"
} > "$REPORT"

MSG="🔍 تقرير تدقيق القبو جاهز (${DATE}).
افتحه في Obsidian: ${REPORT}"
[ -n "$GH" ] && MSG="${MSG}
${GH}/$(python3 -c "import urllib.parse,sys;print('/'.join(urllib.parse.quote(p) for p in sys.argv[1].split('/')))" "$REPORT")"
curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
  --data-urlencode "chat_id=${CHAT}" --data-urlencode "text=${MSG}" >/dev/null
echo "$(date -u +%FT%TZ) report saved: $REPORT" >> "$LOG"
