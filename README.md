![Personal Knowledge Brain](github_banner.svg)
# 🧠 Personal Knowledge Brain

> A self-hosted personal knowledge pipeline that captures, organizes, and retrieves anything you save — links, voice notes, images — via Telegram and WhatsApp.

**Built by [Abdullah Altamimi (@AbOd)](https://github.com/AbOdWs)**

---

## العربية | Arabic

### ما هو هذا المشروع؟

نظام شخصي لحفظ المعرفة يعمل على خادمك الخاص. أرسل أي رابط أو ملاحظة صوتية أو صورة إلى بوت تيليغرام أو واتساب، وسيقوم النظام تلقائياً بتصنيفها وتلخيصها وحفظها في ملفات منظمة — تعمل كـ "دماغ" رقمي شخصي متصل بـ Obsidian.

### المميزات

- 🔗 **حفظ الروابط** — تصنيف تلقائي بالذكاء الاصطناعي + تلخيص
- 🎤 **الملاحظات الصوتية** — تفريغ صوتي تلقائي (عربي وإنجليزي)
- 🖼 **الصور** — تحليل بالذكاء الاصطناعي ووصف تلقائي
- 📂 **التصنيف الذكي** — فئات مخصصة بالكامل
- 🔍 **البحث بالأسئلة** — اسأل البوت عن أي شيء حفظته
- ⏰ **التذكيرات** — `/remind 2weeks` على أي رابط
- 📊 **التقارير** — ملخص يومي وأسبوعي
- 👥 **المشاركة** — منح الضيوف وصولاً محدوداً لفئات معينة
- 🧠 **Obsidian** — مزامنة تلقائية مع GitHub
- 📱 **واتساب + تيليغرام** — يعمل على كلا المنصتين

### الأوامر

| الأمر | الوصف |
|-------|--------|
| أرسل رابطاً | حفظ وتصنيف تلقائي |
| أرسل ملاحظة صوتية | تفريغ وحفظ |
| أرسل صورة | تحليل وحفظ |
| `/list <فئة>` | عرض الروابط المحفوظة |
| `/tag <رابط> #وسم` | إضافة وسوم |
| `/rules` | قواعد التصنيف |
| `/suggest` | اقتراحات إعادة تنظيم |
| `/rescan` | إعادة تطبيق القواعد |
| `/remind 2weeks` | تذكير مستقبلي |
| `/digest` | إعدادات الملخص اليومي |
| `/invite` | دعوة ضيف |
| `/guests` | عرض الضيوف |
| `/revoke` | إلغاء وصول ضيف |
| `/help` | عرض كل الأوامر |

يسعدني تجربتك لتطبيقي الأول على ايفون apps.abod.ws/aish

---

## English

### What is this?

A self-hosted personal knowledge pipeline running on your own VPS. Send any link, voice note, or image to a Telegram or WhatsApp bot — it automatically categorizes, summarizes, and stores everything in organized Markdown files. Ask the bot questions and it retrieves answers from your saved knowledge. Syncs with Obsidian as your visual brain.

### Features

- 🔗 **Link saving** — AI-powered auto-categorization + summarization
- 🎤 **Voice notes** — auto-transcription (Arabic & English)
- 🖼 **Images** — AI vision analysis and description
- 📂 **Smart categories** — fully custom, AI decides
- 🔍 **Natural language queries** — ask anything about what you saved
- ⏰ **Reminders** — `/remind 2weeks` on any entry
- 📊 **Reports** — daily digest + weekly report
- 👥 **Guest access** — share specific categories with family/friends
- 🧠 **Obsidian sync** — auto-sync via GitHub
- 📱 **WhatsApp + Telegram** — works on both

### Commands

| Command | Description |
|---------|-------------|
| Send a URL | Auto-save and categorize |
| Send a voice note | Transcribe and save |
| Send an image | Analyze and save |
| `/list <category>` | Browse saved links |
| `/tag <url> #tag` | Add tags |
| `/rules` | Manage categorization rules |
| `/suggest` | AI reorganization suggestions |
| `/rescan` | Re-apply rules to all entries |
| `/remind 2weeks` | Set a future reminder |
| `/digest` | Configure daily digest |
| `/invite` | Invite a guest |
| `/guests` | View active guests |
| `/revoke` | Remove guest access |
| `/help` | Show all commands |

---

## Architecture

```
Telegram / WhatsApp
       ↓
    n8n (workflows)
       ↓
  ┌────────────────────────────┐
  │  Save link                 │  ← Firecrawl + yt-dlp + oEmbed
  │  Transcribe voice          │  ← Groq Whisper API
  │  Analyze image             │  ← Groq Vision
  │  Answer questions          │  ← Groq LLaMA 3.3 70B
  └────────────────────────────┘
       ↓
  Markdown files on VPS
  /knowledge/travel.md
  /knowledge/ai.md
  /knowledge/tech.md
  ...
       ↓
  GitHub (private repo)
       ↓
  Obsidian (Mac + iPhone)
```

---

## Requirements

- VPS (4GB+ RAM, 20GB+ disk) — [Get Hostinger VPS](https://www.hostinger.com?REFERRALCODE=GIQKABOD9A2H)
- [n8n](https://n8n.io) — workflow automation (self-hosted via Docker)
- [Groq API](https://console.groq.com) — free LLM + Whisper (no cost for personal use)
- [Firecrawl](https://firecrawl.dev) — web scraping (free tier: 500 pages/month)
- Telegram Bot Token — from [@BotFather](https://t.me/BotFather)
- GitHub account — for Obsidian sync
- Obsidian — for visual knowledge browsing

---

## Setup Guide

### Step 1 — Get a VPS

Get a VPS with at least 4GB RAM. Recommended: [Hostinger KVM 4](https://www.hostinger.com?REFERRALCODE=GIQKABOD9A2H) (use this referral link for a discount).

Install Ubuntu 24.04 when setting up.

### Step 2 — Install n8n on your VPS

Hostinger's panel makes this easy — use the **App Installer** to install n8n with one click. It sets up Docker, Traefik, and n8n automatically with SSL.

### Step 3 — Get your API keys

| Service | Where to get it | Cost |
|---------|----------------|------|
| Groq API | [console.groq.com](https://console.groq.com) → API Keys | Free |
| Firecrawl | [firecrawl.dev](https://firecrawl.dev) → Dashboard | Free (500/mo) |
| Telegram Bot | Message [@BotFather](https://t.me/BotFather) → /newbot | Free |

### Step 4 — Create the knowledge folder

SSH into your VPS (use Hostinger's browser terminal):

```bash
mkdir -p /root/knowledge
chmod 777 /root/knowledge
```

### Step 5 — Create the config file

```bash
cp config.example.json /root/config.json
nano /root/config.json
```

Fill in all your API keys and settings. Your Telegram user ID can be found by messaging [@userinfobot](https://t.me/userinfobot).

### Step 6 — Install the VPS scripts

```bash
# Install dependencies
pip3 install yt-dlp --break-system-packages

# Copy scripts to VPS
cp ytdlp-api.py /root/ytdlp-api.py
cp whisper-api.py /root/whisper-api.py

# Create systemd services
cat << 'EOF' > /etc/systemd/system/ytdlp-api.service
[Unit]
Description=yt-dlp metadata API
After=network.target

[Service]
ExecStart=/usr/bin/python3 /root/ytdlp-api.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

cat << 'EOF' > /etc/systemd/system/whisper-api.service
[Unit]
Description=Whisper transcription API
After=network.target

[Service]
ExecStart=/usr/bin/python3 /root/whisper-api.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ytdlp-api whisper-api
systemctl start ytdlp-api whisper-api
```

### Step 7 — Update n8n docker-compose

Find your n8n docker-compose file:
```bash
find /docker -name "docker-compose.yml" | grep n8n
```

Add these environment variables and volume mounts:

```yaml
environment:
  - NODE_FUNCTION_ALLOW_BUILTIN=*
  - NODE_FUNCTION_ALLOW_EXTERNAL=*

volumes:
  - /root/config.json:/home/node/config.json
  - /root/knowledge:/home/node/knowledge
  - /root/guests.json:/home/node/guests.json
  - /root/rules.json:/home/node/rules.json
  - /root/digest_settings.json:/home/node/digest_settings.json
  - /root/pending_suggestions.json:/home/node/pending_suggestions.json
```

Create the supporting files:
```bash
echo "[]" > /root/guests.json
echo "[]" > /root/rules.json
echo "[]" > /root/pending_suggestions.json
cat << 'EOF' > /root/digest_settings.json
{"enabled":true,"time":"09:00","summary":true,"categories":true,"voice":true,"images":true,"stats":true,"motivation":true}
EOF
chmod 777 /root/guests.json /root/rules.json /root/pending_suggestions.json /root/digest_settings.json
```

Restart n8n:
```bash
cd /docker/n8n && docker compose down && docker compose up -d
```

### Step 8 — Find your Docker bridge IP

```bash
docker inspect <your-n8n-container-name> | grep Gateway
```

Update `ytdlp_api_url` and `whisper_api_url` in your config.json to use this IP instead of `172.19.0.1`.

### Step 9 — Import the n8n workflows

In n8n:
1. Go to Workflows → Add workflow → ⋯ → Import from file
2. Import `workflows/main-workflow.json`
3. Import `workflows/reminders-workflow.json`
4. Import `workflows/weekly-report-workflow.json`
5. Add your Telegram credentials to the Telegram nodes
6. Activate each workflow

### Step 10 — Set up Obsidian sync (optional)

1. Create a private GitHub repo named `my-brain`
2. In your VPS knowledge folder:
```bash
cd /root/knowledge
git init
git remote add origin https://YOUR_USERNAME:YOUR_PAT@github.com/YOUR_USERNAME/my-brain.git
git add . && git commit -m "initial" && git push -u origin main
```
3. Add a cron job for auto-push:
```bash
crontab -e
# Add: */5 * * * * cd /root/knowledge && git add . && git commit -m "sync" --allow-empty && git push 2>/dev/null
```
4. In Obsidian: open `~/Documents/my-brain` as a vault, install Obsidian Git plugin, set auto-pull to 5 minutes

### Step 11 — WhatsApp (optional)

```bash
cd /root
mkdir whatsapp-bot && cd whatsapp-bot
cp /path/to/repo/whatsapp-bot/index.js .
cp /path/to/repo/whatsapp-bot/package.json .
npm install
```

Install dependencies:
```bash
apt install -y chromium-browser
apt install -y libatk1.0-0 libatk-bridge2.0-0 libcups2 libdrm2 libxkbcommon0 libxcomposite1 libxdamage1 libxfixes3 libxrandr2 libgbm1 libasound2t64
```

Set up as a service and scan QR code with a dedicated WhatsApp number.

---

## Folder Structure

```
/root/
├── config.json              # Your API keys (never commit this)
├── knowledge/               # Your saved links (never commit this)
│   ├── travel.md
│   ├── ai.md
│   ├── tech.md
│   └── ...
├── guests.json              # Guest access list
├── rules.json               # Categorization rules
├── digest_settings.json     # Daily digest settings
├── ytdlp-api.py             # Video metadata API (port 8765)
├── whisper-api.py           # Transcription API (port 8766)
└── whatsapp-bot/
    └── index.js             # WhatsApp bot
```

---

## Cost Breakdown

| Service | Cost |
|---------|------|
| Hostinger VPS KVM 4 | ~$8/month |
| Groq API | Free |
| Firecrawl | Free (500 pages/month) |
| Telegram | Free |
| WhatsApp | Free (needs a dedicated number) |
| **Total** | **~$8/month** |

---

## Credits

Built by [Abdullah Altamimi (@AbOd)](https://github.com/AbOdWs)

If this helped you, consider using the [Hostinger referral link](https://www.hostinger.com?REFERRALCODE=GIQKABOD9A2H) when getting your VPS.

Please check my first iOS App apps.abod.ws/aish

---

## License

MIT — use it, modify it, share it.
