#!/usr/bin/env python3
# Travel Concierge — dedicated deterministic bot for My Emperor (owner-only).
# Real slash commands (and bare keywords) that ALWAYS do exactly what they say.
# Shares the store /root/travel/bookings.json with the reminder engine.
import json, time, urllib.request, urllib.parse, re, subprocess, os, datetime, html

CFG = json.load(open("/root/config.json"))
CC = json.load(open("/root/concierge.json"))          # {"telegram_bot_token": "..."}
EXP = json.load(open("/root/expenses.json"))          # google-sheet connector
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
"\n— المصروفات —\n"
"أرسل صورة إيصال أو الصق رسالة البنك وسأسجّلها في جدول الرحلة\n"
"trip <اسم التبويب> — حدّد رحلة المصروفات الحالية (trip لعرضها)\n"
"\n/help — هذه القائمة\n"
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


def groq(messages, max_tokens=700, temp=0.2, model="llama-3.3-70b-versatile"):
    body = json.dumps({"model": model, "temperature": temp,
                       "max_tokens": max_tokens, "messages": messages}).encode()
    req = urllib.request.Request("https://api.groq.com/openai/v1/chat/completions", data=body,
                                 headers={"Content-Type": "application/json", "Authorization": "Bearer " + GROQ,
                                          "User-Agent": "curl/8.0"})
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


# ---- expenses ----
import base64

EXP_TAB_FILE = "/root/travel/expense-tab.txt"
CARDMAP_FILE = "/root/travel/card-last4.json"

BANK_SIGNALS = ["شراء", "نقاط بيع", "نقطة بيع", "مدى", "بطاقة", "مبلغ", "حسم", "خصم", "سحب", "عملية",
                "شرائية", "purchase", "pos", "card ending", "ending", "debit", "transaction",
                "الراجحي", "الأهلي", "الانماء", "الإنماء", "alinma", "amex", "urpay", "stcpay", "d360",
                "barq", "mada", "apple pay", "نقاط", "ريال", "sar", "cny", "yuan", "يوان", "usd"]

def looks_like_bank_sms(t):
    low = t.lower()
    if not re.search(r"\d[\d,]*\.?\d*", t):
        return False
    return sum(1 for s in BANK_SIGNALS if s in low) >= 2

def card_map():
    try: return json.load(open(CARDMAP_FILE))
    except Exception: return dict(EXP.get("card_last4", {}))

def set_card(last4, name):
    m = card_map(); m[str(last4)] = name; json.dump(m, open(CARDMAP_FILE, "w"), ensure_ascii=False, indent=2)


def cur_tab():
    try:
        t = open(EXP_TAB_FILE).read().strip()
        return t or EXP["tab"]
    except Exception:
        return EXP["tab"]

def set_tab(name):
    open(EXP_TAB_FILE, "w").write(name.strip())

def exp_post(payload):
    payload["token"] = EXP["secret"]
    payload["tab"] = cur_tab()
    data = json.dumps(payload).encode()
    try:
        r = urllib.request.urlopen(urllib.request.Request(EXP["webapp_url"], data=data,
            headers={"Content-Type": "application/json"}), timeout=40)
        return json.load(r)
    except Exception as e:
        return {"ok": False, "error": str(e)}


def photo_b64(file_id):
    info = tg("getFile", file_id=file_id)
    path = info.get("result", {}).get("file_path")
    if not path:
        return ""
    try:
        raw = urllib.request.urlopen(f"https://api.telegram.org/file/bot{TOKEN}/{path}", timeout=40).read()
        return base64.b64encode(raw).decode()
    except Exception:
        return ""


EXP_RULES = ("Currencies allowed (use EXACTLY one): " + ", ".join(EXP["currencies"]) +
             ". Cards allowed (use EXACTLY one of these or empty): " + ", ".join(EXP["cards"]) +
             ". Date format DD/MM. Categories go in ITEM (short). Comply with the owner's privacy/values, no emojis.")


def parse_expense_json(s):
    m = re.search(r"\{[\s\S]*\}", s or "")
    if not m:
        return None
    txt = re.sub(r"(?<=\d),(?=\d{3}\b)", "", m.group(0))   # strip thousands separators (4,424 -> 4424)
    try:
        return json.loads(txt)
    except Exception:
        return None


def to_amount(v):
    try:
        return float(re.sub(r"[^\d.]", "", str(v)))
    except Exception:
        return None


def extract_receipt(b64):
    sysmsg = ("Extract ONE expense from this receipt image. Return ONLY JSON: "
              "{\"item\":\"short what it is\",\"seller\":\"merchant\",\"date\":\"DD/MM\",\"amount\":number,"
              "\"currency\":\"one of allowed\",\"card\":\"one of allowed or empty\",\"notes\":\"\"}. " + EXP_RULES)
    resp = groq([
        {"role": "user", "content": [
            {"type": "image_url", "image_url": {"url": "data:image/jpeg;base64," + b64}},
            {"type": "text", "text": sysmsg}]}
    ], max_tokens=400, model="meta-llama/llama-4-scout-17b-16e-instruct")
    return parse_expense_json(resp)


def extract_sms(text):
    sysmsg = ("This is a bank SMS for a card transaction. Extract the PURCHASE: the amount charged at the "
              "merchant and ITS currency — IGNORE balance, available limit, fees, and exchange rate. "
              "If both a local amount and a card-billing amount appear, use the amount actually charged at the "
              "merchant (e.g. 'used at X for : SAR 4424' -> amount 4424, currency SAR). "
              "Return ONLY JSON with amount as a plain number (no commas, no currency word). "
              "For card: ALWAYS leave it empty string — card name is resolved separately. "
              "For card4: extract ONLY the literal digits that appear after 'ending in' or 'ending with' in the SMS; if none found leave empty. "
              '{"seller":"merchant","date":"DD/MM","amount":number,"currency":"one of allowed",'
              '"card":"","card4":"digits only or empty","notes":""}. ' + EXP_RULES)
    resp = groq([{"role": "system", "content": sysmsg}, {"role": "user", "content": text[:1500]}], max_tokens=300)
    return parse_expense_json(resp)


def log_expense(d, settle=False):
    amt = to_amount(d.get("amount")) if d else None
    if not amt:
        say("لم أستطع قراءة المبلغ. أعد الإرسال بوضوح أو أرسل النص يدوياً.")
        return
    cur = d.get("currency") if d.get("currency") in EXP["currencies"] else "SAR"
    card = d.get("card") if d.get("card") in EXP["cards"] else ""
    card4 = re.sub(r"\D", "", str(d.get("card4") or ""))[-4:]
    cmap = card_map()
    if not card and card4 and card4 in cmap:
        card = cmap[card4]
    fields = {"item": d.get("item", ""), "seller": d.get("seller", ""), "date": d.get("date", ""),
              "currency": cur, "card": card, "notes": d.get("notes", ""), "conversion": 0}
    if cur == "SAR":
        fields["sar"] = amt; fields["other"] = 0
        action = "add"
    else:
        fields["other"] = amt          # foreign: SAR stays pending until the bank settles
        action = "add"
    if settle:                          # a bank SMS settling a prior foreign purchase
        fields["action"] = "settle"; fields["sar"] = amt
        if cur == "SAR": fields["other"] = None
    else:
        fields["action"] = action
    r = exp_post(fields)
    if r.get("ok"):
        where = "سُوّيت SAR في صف سابق" if r.get("settled") else f"أُضيف صف {r.get('added','')}"
        line = f"سُجّل المصروف ({where}) في [{r.get('tab', cur_tab())}]:\n{fields.get('item') or fields.get('seller')} — {amt} {cur}"
        if card: line += f" — {card}"
        elif card4: line += f"\nالبطاقة المنتهية بـ {card4} غير معروفة — عرّفها مرة واحدة: card {card4} <اسم البطاقة>"
        say(line)
    else:
        say("تعذّر الكتابة إلى الجدول: " + str(r.get("error")))


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
    elif low.startswith("/card") or low.strip() == "card" or re.match(r"^/?card\s+\d", low):
        rest = arg_after("/card", "card").strip()
        parts = rest.split(None, 1)
        if len(parts) >= 2:
            # strip angle brackets from name in case user typed <Amex> literally
            name = parts[1].strip().strip("<>").strip()
            # each token is a last-4 (digits only, or literal like xxxx for testing)
            l4s = [re.sub(r"\D", "", x)[-4:] or x.strip() for x in re.split(r"[,،\s]+", parts[0]) if x.strip()]
            l4s = [x for x in l4s if x]
            for l4 in l4s:
                set_card(l4, name)
            say(f"رُبطت البطاقة ({name}) بالأرقام: " + "، ".join(l4s))
        else:
            m = card_map()
            say("بطاقاتك المعرّفة:\n" + ("\n".join(f"...{k} = {v}" for k, v in m.items()) if m else "لا شيء بعد.") +
                "\n\nعرّف بطاقة: card <آخر 4> <اسم>\nيمكن إضافة أكثر من رقم لنفس البطاقة (الفعلي + Apple Pay): card 1234,5678 Amex")
    elif low.startswith(("/car", "car", "سيارة", "سيارتي")):
        cmd_car(arg_after("/car", "car", "سيارتي في", "سيارتي", "سيارة"))
    elif low.startswith(("/plan", "plan", "خطط", "خطّط")):
        cmd_plan(arg_after("/plan", "plan", "خطط يومي", "خطّط يومي", "خطط", "خطّط"))
    elif low.startswith(("/trip", "trip", "رحلة الحالية", "/tab", "tab")):
        name = arg_after("/trip", "trip", "/tab", "tab", "رحلة الحالية")
        if name:
            set_tab(name); say("رحلة المصروفات الحالية: " + name)
        else:
            say("رحلة المصروفات الحالية: " + cur_tab() + "\nللتغيير: trip <اسم التبويب>")
    elif low.startswith(("/exp", "exp", "مصروف", "expense")):
        log_expense(extract_sms(arg_after("/exp", "exp", "مصروف", "expense")), settle=False)
    else:
        body = arg_after("/travel", "travel", "حجز")
        raw = body if body else t
        # bank SMS detection is deterministic; only fall back to the classifier when unsure
        if looks_like_bank_sms(raw):
            log_expense(extract_sms(raw), settle=True)
        else:
            kind = groq([{"role": "system", "content": "Classify the message as exactly one word: booking (flight/hotel/restaurant reservation confirmation), expense (a bank transaction or purchase/payment notice), or other. One word only."},
                         {"role": "user", "content": raw[:800]}], max_tokens=4, temp=0).lower()
            if "expense" in kind:
                log_expense(extract_sms(raw), settle=True)
            else:
                ingest(raw)


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
                photo = m.get("photo")
                if photo:
                    say("أقرأ الإيصال...")
                    b64 = photo_b64(photo[-1]["file_id"])     # largest size
                    if b64: log_expense(extract_receipt(b64), settle=False)
                    else: say("تعذّر قراءة الصورة.")
                    continue
                text = m.get("text") or m.get("caption") or ""
                if text:
                    handle(text, m)
        except Exception:
            time.sleep(5)
        time.sleep(1)


if __name__ == "__main__":
    main()
