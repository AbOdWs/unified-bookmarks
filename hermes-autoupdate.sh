#!/bin/bash
# Guarded weekly auto-update for the Hermes agent (abodwsbot). Updates the code, restarts,
# then re-asserts the customizations updates have historically clobbered:
#   ownership (via fix-ownership.sh), the owner-lock, and the Gemini provider.
C=hermes-agent-gnyc-hermes-agent-1
H=/opt/hermes/.venv/bin/hermes
LOG=/root/hermes-update.log
echo "$(date -u +%FT%TZ) === auto-update start ===" >> "$LOG"
docker exec -u hermes -e HOME=/opt/data/home "$C" "$H" update -y >> "$LOG" 2>&1
docker restart "$C" >/dev/null 2>&1; sleep 12
/root/fix-ownership.sh
# re-assert owner-lock and Gemini provider only if an update reset them (targeted, safe)
docker exec "$C" sh -c "grep -q \"allowed_chats: '10242904'\" /opt/data/config.yaml || sed -i \"s/^  allowed_chats: .*/  allowed_chats: '10242904'/\" /opt/data/config.yaml"
docker exec "$C" python3 -c "import json;p='/opt/data/auth.json';d=json.load(open(p));\
(d.get('active_provider')=='gemini') or (d.__setitem__('active_provider','gemini') or json.dump(d,open(p,'w'),indent=2))" 2>/dev/null
docker restart "$C" >/dev/null 2>&1; sleep 10; /root/fix-ownership.sh
VER=$(docker exec "$C" cat /opt/data/.update_check 2>/dev/null)
echo "$(date -u +%FT%TZ) === done: $VER ===" >> "$LOG"
TOK=$(docker exec "$C" sh -c "grep ^TELEGRAM_BOT_TOKEN= /opt/data/.env | cut -d= -f2-" | tr -d '"')
[ -n "$TOK" ] && curl -s -X POST "https://api.telegram.org/bot${TOK}/sendMessage" --data-urlencode chat_id=10242904 --data-urlencode "text=تحديث hermes تلقائي اكتمل. $VER" >/dev/null
