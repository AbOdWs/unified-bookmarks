#!/usr/bin/env python3
# Travel Concierge — dedicated deterministic bot for My Emperor (owner-only).
# Real slash commands (and bare keywords) that ALWAYS do exactly what they say.
# Shares the store /root/travel/bookings.json with the reminder engine.
import json, time, urllib.request, urllib.parse, re, subprocess, os, datetime, html

CFG = json.load(open("/root/config.json"))
CC = json.load(open("/root/concierge.json"))          # {"telegram_bot_token": "..."}
TOKEN = CC["telegram_bot_token"]
OWNER = str(CFG["telegram_chat_id"])
GROQ = CFG["groq_api_key"]
API = f"https://api.telegram.org/bot{TOKEN}"
STORE = "/root/travel/bookings.json"
STATE = "/root/travel/concierge-state.json"
KN = "/root/knowledge"
SAUDI = datetime.timezone(datetime.timedelta(hours=3))

HELP = (
"أوامر المرشد السياحي:\n"
"/travel <نص الحجز>  أو  حوّل/الصق تأكيد حجز — يضيفه (طيران/فندق/مطعم/معلم)\n"
"/list — حجوزاتي والعدّ التنازلي\n"
"/del <id|all> — احذف حجزاً أو امسح الكل\n"
"/car <الموقع> — احفظ موقع سيارتي  ·  /car — أين سيارتي\n"
"/plan <مدينة> — خطّط يومي (من معرفتي ثم اقتراحات)\n"
"/help — هذه القائمة\n"
"يمكن إرسال ملف PDF لتذكرة/حجز وسأقرأه."
)


def tg(method, **p):
    data = urllib.parse.urlencode(p).encode()
    try:
        return json.load(urllib.request.urlopen(urllib.request.Request(f"{API}/{method}", data=data), timeout=40))
    except Exception as e:
        return {"ok": False, "error": str(e)}


def load(p, d):
    try: return json.load(open(p))
    except Exception: return d


def save(p, o):
    json.dump(o, open(p, "w"), ensure_ascii=False, indent=2)


def say(text):
    tg("sendMessage", chat_id=OWNER, text=text)


def groq(messages, max_tokens=700, temp=0.2):
    body = json.dumps({"model": "llama-3.3-70b-versatile", "temperature": temp,
                       "max_tokens": max_tokens, "messages": messages}).encode()
    req = urllib.request.Request("https://api.groq.com/openai/v1/chat/completions", data=body,
                                 headers={"Content-Type": "application/json", "Authorization": "Bearer " + GROQ})
    try:
        r = json.load(urllib.request.urlopen(req, timeout=60))
        return r["choices"][0]["message"]["content"].strip()
    except Exception as e:
        return ""


def countdown(start):
    try:
        dt = datetime.datetime.fromisoformat(start)
        if dt.tzinfo is None: dt = dt.replace(tzinfo=SAUDI)
        days = (dt - datetime.datetime.now(datetime.timezone.utc)).total_seconds() / 86400
        if days < 0: return "مضى"
        if days < 1: return f"بعد {int(days*24)} ساعة"
        return f"بعد {int(days)} يوم"
    except Exception:
        return ""


# ---- commands ----
def cmd_list():
    b = load(STORE, [])
    items = [x for x in b if x.get("type") not in ("car",)]
    if not items:
        say("لا حجوزات مسجّلة. أرسل تأكيد حجز أو PDF لأضيفه.")
        return
    items.sort(key=lambda x: x.get("start", ""))
    lines = ["حجوزاتك:"]
    for x in items:
        lines.append(f"- [{x.get('id')}] {x.get('title','')} — {x.get('start','')[:16]} ({countdown(x.get('start',''))})")
    car = [x for x in b if x.get("type") == "car"]
    if car: lines.append(f"\nالسيارة: {car[-1].get('location','')}")
    say("\n".join(lines))


def cmd_delete(arg):
    b = load(STORE, [])
    if arg.strip().lower() == "all":
        n = len([x for x in b if x.get("type") != "car"])
        b = [x for x in b if x.get("type") == "car"]
        save(STORE, b); say(f"حُذفت كل الحجوزات ({n}).")
        return
    ids = [a for a in re.split(r"[\s,]+", arg.strip()) if a]
    before = len(b)
    b = [x for x in b if str(x.get("id")) not in ids]
    save(STORE, b)
    say(f"حُذف {before - len(b)} عنصر." if before != len(b) else "لم أجد هذا الـid. جرّب /list.")


def cmd_car(arg):
    b = load(STORE, [])
    if not arg.strip():
        car = [x for x in b if x.get("type") == "car"]
        say(("سيارتك: " + car[-1].get("location", "")) if car else "لم تسجّل موقع سيارتك بعد. أرسل: /car <الموقع>")
        return
    b = [x for x in b if x.get("type") != "car"]
    b.append({"id": "car", "type": "car", "title": "موقع السيارة", "location": arg.strip(),
              "start": datetime.datetime.now(SAUDI).isoformat()})
    save(STORE, b); say("حُفظ موقع السيارة: " + arg.strip())


def ingest(text):
    parsed = groq([
        {"role": "system", "content": "Extract travel bookings from the text. Return ONLY a JSON array; each item: "
         "{\"type\":\"flight|hotel|restaurant|attraction\",\"title\":\"short\",\"start\":\"ISO8601 with timezone offset; "
         "for flights use departure local time\",\"end\":\"ISO8601 or empty\",\"location\":\"\",\"city\":\"\",\"details\":\"flight no/ref/seats/etc\"}. "
         "If none found return []. No prose."},
        {"role": "user", "content": text[:6000]}
    ], max_tokens=900)
    m = re.search(r"\[[\s\S]*\]", parsed or "")
    if not m:
        say("لم أتعرّف على حجز في هذا النص. الصق التفاصيل أو أرسل PDF.")
        return
    try:
        items = json.loads(m.group(0))
    except Exception:
        say("تعذّر تحليل الحجز. حاول مجدداً.")
        return
    if not items:
        say("لم أجد حجزاً في النص.")
        return
    b = load(STORE, [])
    added = []
    for it in items:
        if not it.get("title"): continue
        slug = re.sub(r"[^a-z0-9]+", "-", (it.get("title", "")[:24]).lower()).strip("-") or "bk"
        it["id"] = slug + "-" + str(int(time.time()) % 100000)
        it["reminders_sent"] = []
        b.append(it); added.append(it)
        time.sleep(0.01)
    save(STORE, b)
    say("أُضيف:\n" + "\n".join(f"- [{x['id']}] {x.get('title')} — {x.get('start','')[:16]}" for x in added) + "\n\nتذكيرات الطيران: 14/7/3/1 يوم + 3 ساعات.")


def cmd_plan(city):
    city = city.strip()
    # read the brain: cards mentioning the city
    cards = []
    try:
        import glob
        for p in glob.glob(KN + "/wiki/**/*.md", recursive=True):
            t = open(p, encoding="utf-8", errors="replace").read()
            if (city and city.lower() in t.lower()) or (city and city in t):
                cards.append(t[:1500])
            if len(cards) >= 10: break
    except Exception:
        pass
    b = load(STORE, [])
    today_books = [x for x in b if x.get("type") not in ("car",)]
    ctx = "\n\n".join(cards)[:12000]
    fixed = "\n".join(f"- {x.get('title')} @ {x.get('start','')[:16]}" for x in today_books)
    ans = groq([
        {"role": "system", "content": "أنت مرشد سفر شخصي للإمبراطور عبدالله. خطّط يوماً عملياً مقسّماً بالوقت اعتماداً على معرفته المحفوظة "
         "(المعطاة) وحجوزاته الثابتة. جمّع الأماكن حسب المنطقة لتقليل التنقل، واذكر أوقات العمل وأوقات الصلاة إن لزم. "
         "بلا إيموجي، التزم بالقيم الإسلامية والسعودية، مختصر."},
        {"role": "user", "content": f"المدينة: {city or 'غير محددة'}\nحجوزاتي الثابتة:\n{fixed or 'لا شيء'}\n\nمن معرفتي المحفوظة:\n{ctx or 'لا شيء محفوظ عن هذه المدينة — اقترح من معرفتك العامة بحذر.'}"}
    ], max_tokens=900)
    say(ans or "تعذّر إعداد الخطة الآن.")


def read_pdf(file_id):
    info = tg("getFile", file_id=file_id)
    path = info.get("result", {}).get("file_path")
    if not path: return ""
    url = f"https://api.telegram.org/file/bot{TOKEN}/{path}"
    tmp = "/tmp/concierge_doc.pdf"
    try:
        urllib.request.urlretrieve(url, tmp)
        out = subprocess.run(["pdftotext", "-layout", tmp, "-"], capture_output=True, text=True, timeout=60)
        os.unlink(tmp)
        return out.stdout
    except Exception:
        return ""


def handle(text, msg):
    t = text.strip()
    low = t.lower()
    def arg_after(*prefixes):
        for p in prefixes:
            if low.startswith(p): return t[len(p):].strip()
        return ""
    if low in ("/start", "/help", "help", "/travel help", "travel help", "/travel", "travel", "سفر", "مرشد"):
        say(HELP)
    elif low.startswith(("/list", "list", "travel list", "حجوزاتي")):
        cmd_list()
    elif low.startswith(("/del", "del", "/travel delete", "travel delete", "احذف")):
        cmd_delete(arg_after("/travel delete", "travel delete", "/del", "del", "احذف"))
    elif low.startswith(("/car", "car", "سيارة", "سيارتي")):
        cmd_car(arg_after("/car", "car", "سيارتي في", "سيارتي", "سيارة"))
    elif low.startswith(("/plan", "plan", "خطط", "خطّط")):
        cmd_plan(arg_after("/plan", "plan", "خطط يومي", "خطّط يومي", "خطط", "خطّط"))
    else:
        # treat anything else (incl. /travel <text> or a pasted/forwarded confirmation) as a booking to ingest
        body = arg_after("/travel", "travel", "حجز")
        ingest(body if body else t)


def main():
    tg("deleteWebhook")
    st = load(STATE, {"offset": 0})
    while True:
        try:
            r = tg("getUpdates", offset=st["offset"], timeout=25)
            for u in r.get("result", []):
                st["offset"] = u["update_id"] + 1
                save(STATE, st)
                m = u.get("message")
                if not m or str(m.get("chat", {}).get("id")) != OWNER:
                    continue
                doc = m.get("document")
                if doc and (doc.get("mime_type") == "application/pdf" or str(doc.get("file_name", "")).lower().endswith(".pdf")):
                    say("أقرأ ملف الحجز...")
                    txt = read_pdf(doc["file_id"])
                    if txt: ingest(txt)
                    else: say("تعذّر قراءة ملف PDF.")
                    continue
                text = m.get("text") or m.get("caption") or ""
                if text:
                    handle(text, m)
        except Exception:
            time.sleep(5)
        time.sleep(1)


if __name__ == "__main__":
    main()
