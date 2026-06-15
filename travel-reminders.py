#!/usr/bin/env python3
# Travel concierge reminder engine. Reads the private booking store and proactively pushes
# reminders to My Emperor via the abodwsbot Telegram bot. Run by cron every 30 min.
# Store: /root/travel/bookings.json  — a list of items:
#   {id, type:flight|hotel|restaurant|attraction|car|note, title, start (ISO, Saudi +03:00 if no tz),
#    end, location, city, details, reminders_sent:[]}
import json, datetime, urllib.request, urllib.parse, subprocess

STORE = "/root/travel/bookings.json"
CHAT = str(json.load(open("/root/config.json"))["telegram_chat_id"])
SAUDI = datetime.timezone(datetime.timedelta(hours=3))
# minutes-before-start to fire (per type)
LEAD = {
    "flight": [24*60, 3*60],
    "hotel": [24*60, 0],
    "restaurant": [120],
    "attraction": [180],
    "default": [120],
}


def bot_token():
    r = subprocess.run(["docker", "exec", "hermes-agent-gnyc-hermes-agent-1", "sh", "-c",
                        "grep '^TELEGRAM_BOT_TOKEN=' /opt/data/.env | cut -d= -f2-"],
                       capture_output=True, text=True, timeout=20)
    return r.stdout.strip().strip('"').strip("'")


def send(token, text):
    data = urllib.parse.urlencode({"chat_id": CHAT, "text": text}).encode()
    try:
        urllib.request.urlopen(urllib.request.Request(f"https://api.telegram.org/bot{token}/sendMessage", data=data), timeout=20)
    except Exception:
        pass


def human(mins):
    if mins >= 1440: return f"{mins//1440} يوم"
    if mins >= 60: return f"{mins//60} ساعة"
    return f"{mins} دقيقة"


def main():
    try:
        bookings = json.load(open(STORE))
    except Exception:
        return
    token = bot_token()
    if not token:
        return
    now = datetime.datetime.now(datetime.timezone.utc)
    changed = False
    for b in bookings:
        if b.get("type") in ("car", "note"):
            continue
        s = b.get("start")
        if not s:
            continue
        try:
            dt = datetime.datetime.fromisoformat(s)
        except Exception:
            continue
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=SAUDI)
        leads = LEAD.get(b.get("type"), LEAD["default"])
        sent = set(str(x) for x in b.get("reminders_sent", []))
        for lead in leads:
            key = str(lead)
            fire = dt - datetime.timedelta(minutes=lead)
            if key not in sent and fire <= now < dt + datetime.timedelta(hours=1):
                when = ("خلال " + human(lead)) if lead > 0 else "الآن"
                loc = b.get("location", "") or b.get("city", "")
                msg = f"تذكير ({b.get('type')}): {b.get('title','')} — {when}"
                if loc: msg += f"\n{loc}"
                if b.get("details"): msg += f"\n{b['details']}"
                send(token, msg.strip())
                sent.add(key)
                changed = True
        b["reminders_sent"] = sorted(sent)
    if changed:
        json.dump(bookings, open(STORE, "w"), ensure_ascii=False, indent=2)


if __name__ == "__main__":
    main()
