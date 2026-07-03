#!/bin/bash
# Deterministic broken-link fixes from the vault audit (Recommendation #2). NO AI, NO quota.
# Makes a git restore point first, then literal find/replace across wiki/ + creates the one
# card two notes ask for. Never deletes. Fully revertible via the printed undo command.
cd /root/knowledge || exit 1
CFG=/root/config.json
DATE=$(date -u +%Y-%m-%d)

git add -A >/dev/null 2>&1
git commit -m "restore point before fix-links ${DATE}" --allow-empty >/dev/null 2>&1
BEFORE=$(git rev-parse HEAD)

# create the card that هندسة-السياق-والأوامر + منظومة-Claude both link to (only if missing)
CARD="wiki/concepts/مكتبات-مهارات-Claude.md"
if [ ! -e "$CARD" ]; then
  cat > "$CARD" <<'CARDEOF'
---
title: مكتبات مهارات Claude
agent: مدقق-القبو
built: PLACEHOLDER_DATE
sources: []
content-depth: metadata-only
---

# مكتبات مهارات Claude

بطاقة جذر مختصرة: «مكتبات المهارات» (Skills) في Claude — حزم قابلة لإعادة الاستخدام
تُعرّف قدرات ومعرفة متخصّصة يستدعيها الوكيل عند الحاجة. أُنشئت لسدّ وصلة مكسورة كانت
مطلوبة من بطاقتين. وسّعها عند مرور محتوى ذي صلة.

## مرتبطة بـ
- [[هندسة-السياق-والأوامر]]
- [[منظومة-Claude-كمنصة-إنتاجية]]
CARDEOF
  sed -i "s/PLACEHOLDER_DATE/${DATE}/" "$CARD"
  echo "created: $CARD"
fi

# literal replacements (Python = no regex/UTF-8 escaping traps). No-op if a string is absent.
python3 - <<'PYEOF'
import glob
repls = [
    ("[[bروتوكول-MCP]]", "[[بروتوكول-MCP]]"),        # latin 'b' typo -> real card
    ("[[توكيل-دورر]]",   "[[تيم-دورر]]"),            # typo -> neighbouring entity
    ("[[دانيال-سان]]",   "دانيال-سان"),              # entity never created -> plain text
    ("[[GoSearch]]",     "GoSearch"),                # item inside a batch, not a card
    ("[[monokern]]",     "monokern"),
    ("[[NineRouter]]",   "NineRouter"),
    ("[[running codex locally with ollama]]", "running codex locally with ollama"),
    ("[[دليل تسوق قوانزو]]", "دليل تسوق قوانزو"),      # internal item reference
    ("[[wikilinks]]",    "wikilinks"),               # explanatory term, not a link
]
changed = 0
for f in glob.glob('wiki/**/*.md', recursive=True):
    s = open(f, encoding='utf-8').read()
    o = s
    for a, b in repls:
        s = s.replace(a, b)
    if s != o:
        open(f, 'w', encoding='utf-8').write(s)
        changed += 1
        print('fixed:', f)
print('link-fix files changed:', changed)
PYEOF

git add -A >/dev/null 2>&1
git commit -m "fix-links ${DATE}: correct 9 broken wikilinks + create مكتبات-مهارات-Claude card" >/dev/null 2>&1 || true
AFTER=$(git rev-parse HEAD)
N=$(git diff --name-only "$BEFORE" "$AFTER" | wc -l | tr -d ' ')

TOKEN=$(python3 -c "import json;print(json.load(open('$CFG'))['telegram_bot_token'])")
CHAT=$(python3 -c "import json;print(json.load(open('$CFG'))['telegram_chat_id'])")
curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
  --data-urlencode "chat_id=${CHAT}" \
  --data-urlencode "text=🔗 إصلاح الروابط تم — ${N} ملف تغيّر (بلا ذكاء اصطناعي، بلا حصة).
للتراجع:
git -C /root/knowledge reset --hard ${BEFORE}" >/dev/null
echo
echo "DONE. $N files changed."
echo "UNDO: git -C /root/knowledge reset --hard $BEFORE"
