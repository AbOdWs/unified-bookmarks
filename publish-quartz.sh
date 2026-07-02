#!/bin/bash
# Build the public site from _public/ with Quartz. BUILD ONLY — does not serve.
# To go live later: wire a web server (nginx/traefik) at /root/quartz/public, then
# enable the cron line at the bottom of this comment. Until then this is dormant.
set -e
export PATH="$HOME/.local/bin:$PATH"
VAULT=/root/knowledge
Q=/root/quartz

# 1) sync approved public cards into Quartz content (never the _pending staging dir)
mkdir -p "$Q/content"
rm -f "$Q/content"/*.md
shopt -s nullglob
copied=0
for f in "$VAULT"/_public/*.md; do
  cp "$f" "$Q/content/"; copied=$((copied+1))
done

# 2) ensure a landing page exists
if [ ! -f "$Q/content/index.md" ]; then
  printf -- "---\ntitle: المحتوى العام\n---\n\nمرحباً — هذه بطاقات منتقاة ومعقّمة للعرض العام.\n" > "$Q/content/index.md"
fi

# 3) static build → /root/quartz/public
cd "$Q"
npx quartz build >/root/quartz-build.log 2>&1
echo "$(date -u +%FT%TZ) quartz build done — $copied public cards → /root/quartz/public" >> /root/quartz-build.log

# To activate later (after WordPress is sorted on abod.ws):
#   - point a web server at /root/quartz/public, and
#   - add cron:  0 5 * * * root /root/publish-quartz.sh >/dev/null 2>&1
