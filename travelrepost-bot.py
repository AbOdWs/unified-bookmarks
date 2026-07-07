#!/usr/bin/env python3
# travelrepost — My Emperor Abdullah's travel content reposter.
# Owner shares a post link -> fetch -> add account to sources.csv -> draft quote ->
# approval (inline buttons) -> on approve, schedule + post to the Telegram channel AND X.
# Also saves every shared link into the knowledge vault (abodlinks sync). Owner-only.
import json, time, urllib.request, urllib.parse, csv, re, os
import hmac, hashlib, base64, secrets

TR = json.load(open("/root/travelrepost.json"))
CFG = json.load(open("/root/config.json"))
TOKEN = TR["telegram_bot_token"]
CHANNEL = TR["channel"]
OWNER = str(CFG["telegram_chat_id"])
GROQ = CFG["groq_api_key"]
YTDLP = CFG["ytdlp_api_url"]
API = f"https://api.telegram.org/bot{TOKEN}"
D = "/root/travelrepost"
SOURCES = "/root/knowledge/travelrepost-sources.csv"
QUEUE = "/root/travelrepost/queue.json"
STATE = "/root/travelrepost/state.json"
DRAFTS = "/root/travelrepost/drafts.json"
INTERVAL = 60           # space scheduled posts 1 min apart
INITIAL = 60            # first post ~1 min out


def tg(method, **params):
    data = urllib.parse.urlencode(params).encode()
    try:
        return json.load(urllib.request.urlopen(urllib.request.Request(f"{API}/{method}", data=data), timeout=40))
    except Exception as e:
        return {"ok": False, "error": str(e)}


def load(p, d):
    try: return json.load(open(p))
    except Exception: return d


def save(p, o):
    json.dump(o, open(p, "w"), ensure_ascii=False, indent=2)


def add_source(platform, handle, url):
    rows = [["platform", "handle", "url", "added", "active", "notes"]]
    try:
        with open(SOURCES) as f:
            rows = [r for r in csv.reader(f) if r]
    except Exception:
        pass
    if not handle:
        return False
    for r in rows[1:]:
        if len(r) >= 2 and r[0] == platform and r[1] == handle:
            return False
    rows.append([platform, handle, url, time.strftime("%Y-%m-%d"), "yes", "auto-added from shared link"])
    with open(SOURCES, "w") as f:
        csv.writer(f).writerows(rows)
    return True


HELP = (
    "أوامر قائمة المتابعة:\n"
    "/list — عرض الحسابات المتابَعة\n"
    "/add tiktok|x @handle — إضافة حساب\n"
    "/remove @handle — إزالة حساب\n"
    "/on @handle — تفعيل · /off @handle — تعطيل\n\n"
    "أو أرسل رابط منشور سفر لإنشاء مسودة إعادة نشر."
)


def _norm(h):
    return h.strip().lstrip("@").lower()


def _read_sources():
    try:
        with open(SOURCES) as f:
            rows = [r for r in csv.reader(f) if r]
    except Exception:
        rows = []
    if not rows or rows[0][:1] != ["platform"]:
        rows = [["platform", "handle", "url", "added", "active", "notes"]] + rows
    return rows


def _write_sources(rows):
    with open(SOURCES, "w") as f:
        csv.writer(f).writerows(rows)


def handle_command(t, chat):
    parts = t.split()
    cmd = parts[0].lower()
    if cmd in ("/list", "/listaccounts"):
        items = [r for r in _read_sources()[1:] if len(r) >= 2 and r[1]]
        if not items:
            tg("sendMessage", chat_id=chat, text="قائمة المتابعة فارغة. أضف حساباً مثل: /add tiktok @handle")
            return
        lines = ["- " + r[0] + ": @" + r[1] + " — " + ("نشط" if (len(r) < 5 or r[4] == "yes") else "معطّل") for r in items]
        tg("sendMessage", chat_id=chat, text="قائمة المتابعة (" + str(len(items)) + "):\n" + "\n".join(lines))
    elif cmd == "/add":
        if len(parts) < 3 or parts[1].lower() not in ("tiktok", "x"):
            tg("sendMessage", chat_id=chat, text="الصيغة: /add tiktok @handle  (المنصّة: tiktok أو x)")
            return
        platform, handle = parts[1].lower(), _norm(parts[2])
        rows = _read_sources()
        if any(len(r) >= 2 and r[0] == platform and r[1] == handle for r in rows[1:]):
            tg("sendMessage", chat_id=chat, text="@" + handle + " موجود مسبقاً في " + platform + ".")
            return
        rows.append([platform, handle, "", time.strftime("%Y-%m-%d"), "yes", "added manually"])
        _write_sources(rows)
        tg("sendMessage", chat_id=chat, text="أُضيف @" + handle + " إلى متابعة " + platform + ".")
    elif cmd == "/remove":
        if len(parts) < 2:
            tg("sendMessage", chat_id=chat, text="الصيغة: /remove @handle")
            return
        handle = _norm(parts[1])
        rows = _read_sources()
        kept = [rows[0]] + [r for r in rows[1:] if not (len(r) >= 2 and r[1] == handle)]
        if len(kept) == len(rows):
            tg("sendMessage", chat_id=chat, text="@" + handle + " غير موجود في القائمة.")
            return
        _write_sources(kept)
        tg("sendMessage", chat_id=chat, text="أُزيل @" + handle + " من القائمة.")
    elif cmd in ("/on", "/off"):
        if len(parts) < 2:
            tg("sendMessage", chat_id=chat, text="الصيغة: " + cmd + " @handle")
            return
        handle, want = _norm(parts[1]), ("yes" if cmd == "/on" else "no")
        rows, found = _read_sources(), False
        for r in rows[1:]:
            if len(r) >= 2 and r[1] == handle:
                while len(r) < 6:
                    r.append("")
                r[4] = want
                found = True
        if not found:
            tg("sendMessage", chat_id=chat, text="@" + handle + " غير موجود في القائمة.")
            return
        _write_sources(rows)
        tg("sendMessage", chat_id=chat, text="@" + handle + (" مُفعّل." if want == "yes" else " مُعطّل."))
    else:
        tg("sendMessage", chat_id=chat, text=HELP)


def fetch_post(url):
    if any(s in url for s in ("tiktok.com", "youtube.com", "youtu.be", "instagram.com")):
        try:
            r = json.load(urllib.request.urlopen(f"{YTDLP}/" + urllib.parse.quote(url, safe=''), timeout=300))
            return ("tiktok" if "tiktok" in url else "video", r.get("uploader", ""), (r.get("content", "") or "")[:2000])
        except Exception:
            return ("video", "", "")
    if "x.com" in url or "twitter.com" in url:
        try:
            r = json.load(urllib.request.urlopen("https://publish.twitter.com/oembed?url=" + urllib.parse.quote(url) + "&omit_script=true", timeout=15))
            t = re.sub(r"\s+", " ", re.sub("<[^>]+>", " ", r.get("html", ""))).strip()
            return ("x", r.get("author_name", ""), t[:2000])
        except Exception:
            return ("x", "", "")
    return ("link", "", "")


def draft_quote(url, platform, author, text):
    sysmsg = ("أنت محرر محتوى سفر للإمبراطور عبدالله. اكتب تعليقاً/اقتباساً عربياً قصيراً (جملة أو جملتين) "
              "لإعادة نشر هذا المحتوى السياحي على قناة سفر، بصوت ملموس مفيد للمسافرين (تأشيرة/أميال/طقس/يستاهل-ما يستاهل) "
              "بلا إنشاء سياحي عام وبلا إيموجي. التزم بالقيم الإسلامية والسعودية؛ إن كان المحتوى مخالفاً (خمر/قمار/تعرٍّ) "
              "أجب فقط بكلمة SKIP. لا تجمع معلومات شخصية.")
    usr = f"المصدر: {platform} — {author}\nالرابط: {url}\nالمحتوى: {text or '(لا نص)'}"
    body = json.dumps({"model": "llama-3.3-70b-versatile", "temperature": 0.5, "max_tokens": 220,
                       "messages": [{"role": "system", "content": sysmsg}, {"role": "user", "content": usr}]}).encode()
    req = urllib.request.Request("https://api.groq.com/openai/v1/chat/completions", data=body,
                                 headers={"Content-Type": "application/json", "Authorization": "Bearer " + GROQ,
                                          # Groq is behind Cloudflare, which 403s (error 1010) the default
                                          # Python-urllib User-Agent. Send a curl UA so the request is allowed.
                                          "User-Agent": "curl/8.4.0"})
    try:
        r = json.load(urllib.request.urlopen(req, timeout=40))
        return r["choices"][0]["message"]["content"].strip()
    except Exception:
        return ""


def save_to_vault(url, platform, author, text):
    """Mirror abodlinkbot: drop the link into raw/inbox/ so ورّاق digests it into the
    knowledge vault. Fire-and-forget — never breaks the repost flow. Skips duplicates.
    Uses the HOST vault path (/root/knowledge); config.knowledge_dir is the n8n container path."""
    try:
        raw = "/root/knowledge/raw"
        for root, _, files in os.walk(raw):
            for fn in files:
                if fn.endswith(".md"):
                    try:
                        if url in open(os.path.join(root, fn), encoding="utf-8", errors="ignore").read():
                            return
                    except Exception:
                        pass
        inbox = os.path.join(raw, "inbox")
        os.makedirs(inbox, exist_ok=True)
        now = time.gmtime()
        stamp = time.strftime("%Y-%m-%d-%H%M", now)
        itype = "video" if platform in ("tiktok", "video") else "link"
        slug_src = author or re.sub(r"https?://(www\.)?", "", url)
        slug = re.sub(r"[^a-z0-9؀-ۿ]+", "-", slug_src.lower()).strip("-")[:60] or "link"
        fname = f"{stamp}-{slug}.md"
        fpath = os.path.join(inbox, fname)
        c = 1
        while os.path.exists(fpath):
            c += 1
            fname = f"{stamp}-{slug}-{c}.md"
            fpath = os.path.join(inbox, fname)
        fm = ["---", "agent: ورّاق", "captured: " + time.strftime("%Y-%m-%dT%H:%M:%SZ", now),
              "type: " + itype, "source: " + url, "content-depth: metadata-only"]
        if author:
            fm.append('title: "' + author.replace('"', "'") + '"')
        fm += ["via: travelrepost", "---"]
        body = ("\n".join(fm) + "\n\n# " + (author or url) + "\n\nSource: " + url + "\n\n"
                + (text or "_(no content could be fetched)_") + "\n")
        with open(fpath, "w", encoding="utf-8") as f:
            f.write(body)
    except Exception:
        pass


def process_link(url, chat):
    platform, author, text = fetch_post(url)
    save_to_vault(url, platform, author, text)  # also add it to abodlinks (the knowledge vault)
    added = add_source(platform, author, url)
    quote = draft_quote(url, platform, author, text)
    if not quote or quote.upper().startswith("SKIP"):
        tg("sendMessage", chat_id=chat, text=f"تخطّيت هذا الرابط (غير مناسب للقيم أو تعذّرت معالجته).\n{url}")
        return
    drafts = load(DRAFTS, {})
    did = str(int(time.time() * 1000) % 100000000)
    drafts[did] = {"url": url, "author": author, "platform": platform, "quote": quote}
    save(DRAFTS, drafts)
    note = (f"\n(أُضيف الحساب «{author}» إلى القائمة)" if added and author else "")
    preview = f"مسودة إعادة نشر:\n\n«{quote}»\n\nالمصدر: {author} — {url}{note}"
    kb = {"inline_keyboard": [[{"text": "نشر (جدولة)", "callback_data": f"ok:{did}"},
                              {"text": "رفض", "callback_data": f"no:{did}"}]]}
    tg("sendMessage", chat_id=chat, text=preview, reply_markup=json.dumps(kb), disable_web_page_preview="false")


def approve(did, chat):
    drafts = load(DRAFTS, {})
    d = drafts.get(did)
    if not d:
        tg("sendMessage", chat_id=chat, text="انتهت صلاحية هذه المسودة.")
        return
    q = load(QUEUE, [])
    post_at = (max(x["post_at"] for x in q) + INTERVAL) if q else (time.time() + INITIAL)
    q.append({"post_at": post_at, **d})
    save(QUEUE, q)
    drafts.pop(did, None)
    save(DRAFTS, drafts)
    xnote = " و X" if TR.get("x_api") else ""
    tg("sendMessage", chat_id=chat, text=f"تمت الموافقة — سيُنشر بعد ~{int((post_at - time.time())/60)} دقيقة على {CHANNEL}{xnote}.")


def reject(did, chat):
    drafts = load(DRAFTS, {})
    drafts.pop(did, None)
    save(DRAFTS, drafts)
    tg("sendMessage", chat_id=chat, text="رُفضت المسودة، لن تُنشر.")


def _xq(s):
    return urllib.parse.quote(str(s), safe="~")


def post_x(quote, url, platform):
    """Post to X: quote-tweet the original if it's an X post, else tweet quote + link. OAuth 1.0a, stdlib."""
    x = TR.get("x_api")
    if not x:
        return None
    m = re.search(r"(?:twitter\.com|x\.com)/[^/]+/status/(\d+)", url or "")
    if m:
        body = {"text": (quote or "")[:280], "quote_tweet_id": m.group(1)}
    else:
        room = max(0, 279 - len(url or ""))
        body = {"text": ((quote or "")[:room] + "\n" + url) if url else (quote or "")[:280]}
    o = {"oauth_consumer_key": x["api_key"], "oauth_nonce": secrets.token_hex(16),
         "oauth_signature_method": "HMAC-SHA1", "oauth_timestamp": str(int(time.time())),
         "oauth_token": x["access_token"], "oauth_version": "1.0"}
    api = "https://api.twitter.com/2/tweets"
    ps = "&".join(f"{_xq(k)}={_xq(v)}" for k, v in sorted(o.items()))
    base = "&".join(["POST", _xq(api), _xq(ps)])
    key = f"{_xq(x['api_secret'])}&{_xq(x['access_secret'])}"
    o["oauth_signature"] = base64.b64encode(hmac.new(key.encode(), base.encode(), hashlib.sha1).digest()).decode()
    hdr = "OAuth " + ", ".join(f'{_xq(k)}="{_xq(v)}"' for k, v in sorted(o.items()))
    req = urllib.request.Request(api, data=json.dumps(body).encode(),
                                 headers={"Authorization": hdr, "Content-Type": "application/json"})
    try:
        r = json.load(urllib.request.urlopen(req, timeout=30))
        return r.get("data", {}).get("id")
    except Exception as e:
        try:
            print("X post failed:", e.read().decode()[:200])
        except Exception:
            print("X post failed:", e)
        return None


def post_due():
    q = load(QUEUE, [])
    now = time.time()
    keep = []
    for it in q:
        if it["post_at"] <= now:
            tg("sendMessage", chat_id=CHANNEL, text=f"{it['quote']}\n\nالمصدر: {it['url']}", disable_web_page_preview="false")
            post_x(it.get("quote", ""), it.get("url"), it.get("platform"))
        else:
            keep.append(it)
    if len(keep) != len(q):
        save(QUEUE, keep)


def main():
    tg("deleteWebhook")  # ensure long-polling works
    st = load(STATE, {"offset": 0})
    while True:
        try:
            post_due()
            r = tg("getUpdates", offset=st["offset"], timeout=25)
            for u in r.get("result", []):
                st["offset"] = u["update_id"] + 1
                save(STATE, st)
                msg = u.get("message")
                cb = u.get("callback_query")
                if msg:
                    if str(msg.get("chat", {}).get("id")) != OWNER:
                        continue
                    t = (msg.get("text") or msg.get("caption") or "").strip()
                    m = re.search(r"https?://[^\s]+", t)
                    if t.startswith("/"):
                        handle_command(t, str(msg["chat"]["id"]))
                    elif m:
                        process_link(m.group(0), str(msg["chat"]["id"]))
                    else:
                        tg("sendMessage", chat_id=str(msg["chat"]["id"]), text="أرسل رابط منشور سفر، أو /help لإدارة قائمة المتابعة.")
                elif cb:
                    if str(cb.get("from", {}).get("id")) != OWNER:
                        continue
                    tg("answerCallbackQuery", callback_query_id=cb["id"])
                    data = cb.get("data", "")
                    chat = str(cb["from"]["id"])
                    if data.startswith("ok:"): approve(data[3:], chat)
                    elif data.startswith("no:"): reject(data[3:], chat)
        except Exception:
            time.sleep(5)
        time.sleep(1)


if __name__ == "__main__":
    main()
