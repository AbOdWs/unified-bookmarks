from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
import subprocess, json, urllib.parse, os, re, tempfile, urllib.request, base64, glob, math

GROQ_KEY = os.environ.get('GROQ_API_KEY', '')
COOKIES_FILE = '/root/yt-cookies.txt'   # export from browser to bypass YouTube bot checks


def ytdlp_cmd(*args):
    cmd = ['yt-dlp']
    if os.path.exists(COOKIES_FILE):
        cmd += ['--cookies', COOKIES_FILE]
    return cmd + list(args)
TRANSCRIPT_CAP = 60000          # chars — full transcript, sanity cap only
WHISPER_CHUNK_SECONDS = 600     # 10-min chunks keep each upload well under Groq's 25MB limit
MAX_AUDIO_SECONDS = 7200        # refuse Whisper path beyond 2h


def clean_subtitle_file(path):
    """VTT/SRT -> plain text."""
    with open(path, 'r', errors='replace') as f:
        raw = f.read()
    lines, out, seen_tail = raw.split('\n'), [], None
    for line in lines:
        line = line.strip()
        if not line or line.isdigit() or '-->' in line:
            continue
        if line.startswith(('WEBVTT', 'Kind:', 'Language:', 'NOTE')):
            continue
        line = re.sub(r'<[^>]+>', '', line).strip()
        if not line or line == '[Music]':
            continue
        # auto-subs repeat rolling lines; drop consecutive duplicates
        if line == seen_tail:
            continue
        seen_tail = line
        out.append(line)
    return ' '.join(out)


def try_captions(url, tmpdir):
    """Try real subs first, then auto-subs. Returns plain text or ''."""
    for flag in ('--write-subs', '--write-auto-subs'):
        subprocess.run(
            ytdlp_cmd(flag, '--skip-download', '--sub-langs', 'ar,en,-live_chat',
                      '-o', os.path.join(tmpdir, 'cap'), url),
            capture_output=True, timeout=60)
        files = glob.glob(os.path.join(tmpdir, 'cap*.vtt')) + \
                glob.glob(os.path.join(tmpdir, 'cap*.srt'))
        if files:
            text = clean_subtitle_file(files[0])
            for f in files:
                os.unlink(f)
            if len(text) > 50:
                return text
    return ''


def whisper_transcribe_file(path):
    result = subprocess.run([
        'curl', '-s', '-X', 'POST',
        'https://api.groq.com/openai/v1/audio/transcriptions',
        '-H', f'Authorization: Bearer {GROQ_KEY}',
        '-F', f'file=@{path}',
        '-F', 'model=whisper-large-v3-turbo',
    ], capture_output=True, text=True, timeout=300)
    return json.loads(result.stdout).get('text', '')


def try_whisper(url, tmpdir, duration):
    """Download audio only and run it through Groq Whisper, chunked if long."""
    if not GROQ_KEY or (duration and duration > MAX_AUDIO_SECONDS):
        return ''
    audio_tpl = os.path.join(tmpdir, 'audio.%(ext)s')
    subprocess.run(
        ytdlp_cmd('-f', 'bestaudio[filesize<100M]/bestaudio', '-x',
                  '--audio-format', 'mp3', '--audio-quality', '32K',
                  '-o', audio_tpl, url),
        capture_output=True, timeout=600)
    audio_files = glob.glob(os.path.join(tmpdir, 'audio.*'))
    if not audio_files:
        return ''
    audio = audio_files[0]
    if duration and duration > WHISPER_CHUNK_SECONDS:
        # split into chunks with ffmpeg, transcribe each, join
        chunk_tpl = os.path.join(tmpdir, 'chunk%03d.mp3')
        subprocess.run(
            ['ffmpeg', '-y', '-i', audio, '-f', 'segment',
             '-segment_time', str(WHISPER_CHUNK_SECONDS), '-c', 'copy', chunk_tpl],
            capture_output=True, timeout=300)
        parts = []
        for chunk in sorted(glob.glob(os.path.join(tmpdir, 'chunk*.mp3'))):
            parts.append(whisper_transcribe_file(chunk))
        return ' '.join(p for p in parts if p)
    return whisper_transcribe_file(audio)


def tiktok_thumbnail_description(data):
    try:
        thumbnails = data.get('thumbnails', [])
        thumb_url = next((t['url'] for t in thumbnails if t.get('preference', -99) == -1), None)
        if not thumb_url and thumbnails:
            thumb_url = thumbnails[0]['url']
        if not thumb_url or not GROQ_KEY:
            return ''
        req = urllib.request.Request(thumb_url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req, timeout=10) as r:
            img_data = base64.b64encode(r.read()).decode()
        payload = json.dumps({
            "model": "meta-llama/llama-4-scout-17b-16e-instruct",
            "messages": [{"role": "user", "content": [
                {"type": "image_url", "image_url": {"url": "data:image/jpeg;base64," + img_data}},
                {"type": "text", "text": "Describe what you see in this video thumbnail in 1-2 sentences. Focus on the main subject and topic."}
            ]}],
            "max_tokens": 150
        }).encode()
        vreq = urllib.request.Request(
            'https://api.groq.com/openai/v1/chat/completions', data=payload,
            headers={'Content-Type': 'application/json', 'Authorization': 'Bearer ' + GROQ_KEY})
        with urllib.request.urlopen(vreq, timeout=20) as r:
            return json.loads(r.read())['choices'][0]['message']['content']
    except Exception:
        return ''


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        url = urllib.parse.unquote(self.path[1:])
        try:
            result = subprocess.run(
                ytdlp_cmd('--dump-json', '--no-download', url),
                capture_output=True, text=True, timeout=45)
            if not result.stdout.strip():
                raise RuntimeError((result.stderr or 'yt-dlp returned no data').strip().split('\n')[-1][:300])
            data = json.loads(result.stdout)
            duration = data.get('duration') or 0

            metadata = ' | '.join(filter(None, [
                data.get('title', ''),
                data.get('uploader', ''),
                data.get('duration_string', ''),
                (data.get('description', '') or '')[:1500],
                ' '.join(data.get('tags', [])[:15]),
            ]))

            # 1) captions, 2) Whisper on audio, else metadata-only
            transcript = ''
            with tempfile.TemporaryDirectory() as tmpdir:
                try:
                    transcript = try_captions(url, tmpdir)
                except Exception:
                    transcript = ''
                if not transcript:
                    try:
                        transcript = try_whisper(url, tmpdir, duration)
                    except Exception:
                        transcript = ''
            transcript = transcript[:TRANSCRIPT_CAP]

            thumb_desc = tiktok_thumbnail_description(data) if 'tiktok.com' in url else ''

            parts = [metadata]
            if thumb_desc:
                parts.append('Thumbnail: ' + thumb_desc)
            if transcript:
                parts.append('Transcript:\n' + transcript)

            body = {
                'content': '\n\n'.join(parts),
                'content_depth': 'transcript' if transcript else 'metadata-only',
                'title': data.get('title', ''),
                'uploader': data.get('uploader', ''),
                'duration': duration,
            }
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(body).encode())
        except Exception as e:
            self.send_response(500)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(
                {'content': '', 'content_depth': 'metadata-only', 'error': str(e)}).encode())

    def log_message(self, *args):
        pass


ThreadingHTTPServer(('0.0.0.0', 8765), Handler).serve_forever()
