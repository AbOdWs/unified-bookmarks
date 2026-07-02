const fs = require('fs');
const path = require('path');
const config = JSON.parse(fs.readFileSync('/home/node/config.json', 'utf8'));

const message = $('Telegram Trigger').item.json.message;
if (!message || !message.text) return [];
let question = message.text.trim();
const senderId = String(message.from?.id || '');
const chatId = String(message.chat?.id || '');

const KN = config.knowledge_dir;
const WIKI = KN + '/wiki';
const PUBLIC = KN + '/_public';
const GH = config.github_base || '';

// HTML is more robust than Markdown for our content (only & < > need escaping) and is the
// only mode where expandable blockquotes work — so citations collapse into a tap-to-expand block.
function htmlEscape(s) { return (s || '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); }

function telegramFormat(answer, meta) {
  if (!answer) return answer;
  const names = [...new Set((answer.match(/\[\[([^\]]+)\]\]/g) || []).map(s => s.slice(2, -2).trim()))];
  // drop the model's own Sources/المصادر line — we build our own
  let prose = answer.replace(/\n*\s*(sources|المصادر|المصدر)\s*:[\s\S]*$/i, '');
  prose = prose.replace(/\[\[([^\]]+)\]\]/g, '$1');   // strip remaining brackets
  prose = htmlEscape(prose).trim();
  let footer = '';
  if (names.length) {
    const items = [];
    for (const n of names) {
      const m = meta[n];
      const cardUrl = (m && m.rel && GH) ? GH + '/wiki/' + m.rel.split('/').map(encodeURIComponent).join('/') : null;
      let line = cardUrl ? '<a href="' + htmlEscape(cardUrl) + '">' + htmlEscape(n) + '</a>' : htmlEscape(n);
      if (m && m.sourceUrl) line += ' — <a href="' + htmlEscape(m.sourceUrl) + '">المصدر</a>';
      items.push('• ' + line);
    }
    footer = '\n\n<blockquote expandable>🔗 المصادر:\n' + items.join('\n') + '</blockquote>';
  }
  return prose + footer;
}

// ---------- helpers ----------
function listCards(subdir) {
  const dir = subdir ? WIKI + '/' + subdir : WIKI;
  let out = [];
  let entries = [];
  try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch(e) { return out; }
  for (const ent of entries) {
    if (ent.isDirectory()) out = out.concat(listCards((subdir ? subdir + '/' : '') + ent.name));
    else if (ent.name.endsWith('.md') && ent.name !== 'index.md') out.push((subdir ? subdir + '/' : '') + ent.name);
  }
  return out;
}
function readCard(rel) {
  try { return fs.readFileSync(WIKI + '/' + rel, 'utf8'); } catch(e) { return ''; }
}
function cardName(rel) { return path.basename(rel, '.md'); }
function firstHeading(txt) { const m = txt.match(/^#\s+(.+)$/m); return m ? m[1].trim() : ''; }
function frontTags(txt) { const m = txt.match(/tags:\s*\[([^\]]*)\]/); return m ? m[1] : ''; }

// Arabic/English-friendly tokenizer
function tokens(s) {
  return (s || '').toLowerCase()
    .replace(/[ً-ٰٟ]/g, '')            // strip Arabic diacritics
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .split(/\s+/).filter(t => t.length >= 2);
}

// append a line under a heading in كاتب's unified store
function appendToTasks(heading, line) {
  const p = KN + '/AIOS/tasks.md';
  let t = '';
  try { t = fs.readFileSync(p, 'utf8'); } catch(e) { t = '---\nagent: كاتب\nupdated: \n---\n\n# المهام والتقويم\n'; }
  const re = new RegExp('(##\\s*' + heading.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '[^\\n]*\\n)');
  if (re.test(t)) t = t.replace(re, '$1' + line + '\n');
  else t += '\n## ' + heading + '\n' + line + '\n';
  t = t.replace(/^updated:.*$/m, 'updated: ' + new Date().toISOString().split('T')[0]);
  fs.writeFileSync(p, t, 'utf8');
}

function loadGuests() { try { return JSON.parse(fs.readFileSync(config.guests_file, 'utf8')); } catch(e) { return []; } }
function saveGuests(g) { fs.writeFileSync(config.guests_file, JSON.stringify(g, null, 2), 'utf8'); }
function isOwner() { return senderId === String(config.telegram_chat_id); }
function getGuest() {
  const today = new Date().toISOString().split('T')[0];
  return loadGuests().find(g => String(g.telegram_id) === senderId && g.expires >= today) || null;
}

// Retrieve top-N relevant wiki cards for a query (start at index, load relevant only — never raw)
async function answerFromWiki(q, restrictDir) {
  const cards = restrictDir ? listCards(restrictDir) : listCards('');
  if (cards.length === 0) return null;
  const qtok = tokens(q);
  const scored = [];
  for (const rel of cards) {
    const txt = readCard(rel);
    const hay = (cardName(rel) + ' ' + firstHeading(txt) + ' ' + frontTags(txt) + ' ' + txt).toLowerCase()
      .replace(/[ً-ٰٟ]/g, '');
    let score = 0;
    for (const t of qtok) { if (hay.includes(t)) score += 1; }
    // weight title/tag hits higher
    const head = (cardName(rel) + ' ' + firstHeading(txt) + ' ' + frontTags(txt)).toLowerCase();
    for (const t of qtok) { if (head.includes(t)) score += 2; }
    if (score > 0) scored.push({ rel, score, txt });
  }
  scored.sort((a, b) => b.score - a.score);
  const top = scored.slice(0, 12);
  if (top.length === 0) return { answer: null, cards: [], meta: {} };

  // metadata for citation links: card path + original source URL (if any)
  const meta = {};
  for (const c of top) {
    // prefer frontmatter source-url; else first http(s) URL anywhere in the card body (batch cards list them)
    const m = c.txt.match(/^source-url:\s*(\S+)/m)
           || c.txt.match(/^source:\s*(https?:\/\/\S+)/m)
           || c.txt.match(/(https?:\/\/[^\s)\]]+)/);
    meta[cardName(c.rel)] = { rel: c.rel, sourceUrl: m ? m[1] : null };
  }

  let context = '';
  let indexTxt = '';
  try { indexTxt = fs.readFileSync(WIKI + '/index.md', 'utf8').slice(0, 2500); } catch(e) {}
  if (indexTxt) context += '=== wiki/index (اللوحة) ===\n' + indexTxt + '\n';
  for (const c of top) context += '\n=== بطاقة: [[' + cardName(c.rel) + ']] ===\n' + c.txt.slice(0, 2500) + '\n';
  context = context.slice(0, 22000);

  const resp = await this.helpers.httpRequest({
    method: 'POST', url: 'https://api.groq.com/openai/v1/chat/completions',
    headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + config.groq_api_key },
    body: { model: 'llama-3.3-70b-versatile', temperature: 0.3, max_tokens: 600,
      frequency_penalty: 0.6, presence_penalty: 0.3, messages: [
      { role: 'system', content: 'You are Abdullah\'s personal knowledge assistant. Answer ONLY from the provided wiki cards — never invent. CRITICAL RULES:\n1) Reply in the SAME language as the question (Arabic question -> Arabic answer; English question -> English answer).\n2) Be concise: 2-5 sentences MAX. Never repeat a sentence or phrase. Stop when answered.\n3) Cite the cards you used as [[card-name]], inline or in a final "Sources:" line.\n4) If the cards do not answer it, say so plainly.' },
      { role: 'user', content: context + '\n\nQuestion: ' + q } ]
    }
  });
  let ans = resp.choices?.[0]?.message?.content || null;
  // safety net: collapse any runaway repetition the model still produces
  if (ans) {
    const sents = ans.split(/(?<=[.!؟\n])\s+/);
    const seen = new Set(); const kept = [];
    for (const s of sents) { const k = s.trim().slice(0, 40); if (k && seen.has(k)) continue; seen.add(k); kept.push(s); }
    ans = kept.join(' ').slice(0, 2000);
  }
  return { answer: ans, cards: top.map(c => cardName(c.rel)), meta };
}

// ====================================================
// OWNER
// ====================================================
if (isOwner()) {
  if (question.startsWith('http')) return [];

  // /invite /guests /revoke — guest management (read from _public in Phase 6)
  if (question.toLowerCase().startsWith('/invite')) {
    const parts = question.split(' ');
    if (parts.length < 4) return { answer: 'Usage: /invite <telegram_id> <topics> <duration>\nمثال: /invite 123456789 travel,food 7days' };
    const guestId = parts[1];
    const categories = parts[2].toLowerCase().split(',').map(c => c.trim().replace(/[^a-z0-9_-]/g, ''));
    const durationStr = parts[3].toLowerCase();
    let expires;
    if (durationStr === 'permanent') expires = '9999-12-31';
    else { const amount = parseInt(durationStr); const unit = durationStr.replace(/[0-9]/g, ''); const d = new Date();
      if (unit.startsWith('day')) d.setDate(d.getDate() + amount); else if (unit.startsWith('week')) d.setDate(d.getDate() + amount * 7); else if (unit.startsWith('month')) d.setMonth(d.getMonth() + amount); expires = d.toISOString().split('T')[0]; }
    const guests = loadGuests();
    const idx = guests.findIndex(g => String(g.telegram_id) === guestId);
    const ng = { telegram_id: guestId, categories, expires, added: new Date().toISOString().split('T')[0] };
    if (idx >= 0) guests[idx] = ng; else guests.push(ng);
    saveGuests(guests);
    return { answer: '✅ دعوة ضيف\n\nID: ' + guestId + '\nالمواضيع: ' + categories.join(', ') + '\nتنتهي: ' + expires };
  }
  if (question.toLowerCase().startsWith('/guests')) {
    const today = new Date().toISOString().split('T')[0];
    const active = loadGuests().filter(g => g.expires >= today);
    if (active.length === 0) return { answer: 'لا ضيوف نشطين.' };
    return { answer: '👥 الضيوف (' + active.length + '):\n\n' + active.map((g, i) => `${i + 1}. ID: ${g.telegram_id}\n   المواضيع: ${g.categories.join(', ')}\n   تنتهي: ${g.expires}`).join('\n\n') };
  }
  if (question.toLowerCase().startsWith('/revoke')) {
    const guestId = question.split(' ')[1];
    if (!guestId) return { answer: 'Usage: /revoke <telegram_id>' };
    let guests = loadGuests(); const before = guests.length;
    guests = guests.filter(g => String(g.telegram_id) !== guestId); saveGuests(guests);
    return { answer: before > guests.length ? '✅ أُلغيت صلاحية ' + guestId : '❌ غير موجود: ' + guestId };
  }

  // /list — browse the wiki (domains via index, or a topic)
  if (question.toLowerCase().startsWith('/list') || question.toLowerCase() === 'list') {
    const arg = question.replace(/^\/?list\s*/i, '').replace(/[،,.؛;]+$/, '').trim();
    if (!arg) {
      let idx = '';
      try { idx = fs.readFileSync(WIKI + '/index.md', 'utf8'); } catch(e) {}
      const domains = (idx.match(/^###\s+(.+)$/gm) || []).map(s => s.replace(/^###\s+/, '')).filter(d => !/أشخاص|متفرقة/.test(d) || true);
      const concepts = listCards('concepts').map(cardName);
      return { answer: '🗂 *مجالات اللوحة:*\n' + (domains.length ? domains.map(d => '• ' + d).join('\n') : '—') + '\n\n💡 المفاهيم (' + concepts.length + '): اكتب /list <موضوع> لتصفّح موضوع، أو افتح wiki/index.md في Obsidian.' };
    }
    // topic listing: matching cards
    const r = await answerFromWiki.call(this, arg, null);
    if (!r || !r.cards.length) return { answer: 'لا بطاقات مطابقة لـ "' + arg + '" في الويكي.' };
    return { answer: '🗂 بطاقات متعلّقة بـ "' + arg + '":\n' + r.cards.map(c => '• [[' + c + ']]').join('\n') };
  }

  // /spec <idea> — فقيه turns an idea into a requirements DRAFT (you approve before وكيل builds)
  if (question.toLowerCase().startsWith('/spec')) {
    const idea = question.replace(/^\/spec\s*/i, '').trim();
    if (!idea) return { answer: 'Usage: /spec <فكرة المشروع>\nفقيه يكتب مسودة متطلبات، تراجعها وتعتمدها قبل أي بناء.' };
    try {
      await this.helpers.httpRequest({ method: 'POST', url: config.build_trigger_url + '/spec', headers: { 'Content-Type': 'application/json' }, body: { idea }, timeout: 10000 });
      return { answer: '📋 فقيه يحضّر مسودة المتطلبات. سأرسلها لك للمراجعة خلال دقائق — لن يُبنى شيء قبل أن تعتمدها (status: approved).' };
    } catch(e) { return { answer: '❌ تعذّر تشغيل فقيه: ' + e.message }; }
  }

  // /research <question> — فقيه writes a research report (options/tradeoffs/recommendation)
  if (question.toLowerCase().startsWith('/research')) {
    const q = question.replace(/^\/research\s*/i, '').trim();
    if (!q) return { answer: 'Usage: /research <سؤال>\nفقيه يكتب تقرير مقارنة في wiki/synthesis.' };
    try {
      await this.helpers.httpRequest({ method: 'POST', url: config.build_trigger_url + '/research', headers: { 'Content-Type': 'application/json' }, body: { idea: q }, timeout: 10000 });
      return { answer: '🔎 فقيه يبحث ويكتب تقريراً. سأرسله لك خلال دقائق.' };
    } catch(e) { return { answer: '❌ تعذّر تشغيل فقيه: ' + e.message }; }
  }

  // /publish [topic] — courier sanitizes cards → _public/_pending for approval.
  //   /publish            → only cards you marked `share: public`
  //   /publish <topic>    → all cards in that topic (e.g. /publish travel)
  if (question.toLowerCase().startsWith('/publish')) {
    const topic = question.replace(/^\/publish\s*/i, '').trim().toLowerCase();
    try {
      await this.helpers.httpRequest({ method: 'POST', url: config.build_trigger_url + '/courier',
        headers: { 'Content-Type': 'application/json' }, body: topic ? { topic } : {}, timeout: 10000 });
      return { answer: topic
        ? 'شغّلت الساعي على موضوع «' + topic + '». سأرسل لك معاينة كل بطاقة معقّمة للموافقة، ثم /approve ' + topic + ' أو /approve all.'
        : 'شغّلت الساعي على البطاقات المعلّمة share: public. سأرسل المعاينات للموافقة.' };
    } catch(e) { return { answer: 'تعذّر تشغيل الساعي: ' + e.message }; }
  }

  // /approve <card> | all | <topic> — move sanitized pending card(s) into _public
  if (question.toLowerCase().startsWith('/approve')) {
    const arg = question.replace(/^\/approve\s*/i, '').trim().replace(/^\[\[|\]\]$/g, '');
    if (!arg) return { answer: 'Usage: /approve <card> | /approve all | /approve <topic>' };
    const pend = PUBLIC + '/_pending';
    let pending = [];
    try { pending = fs.readdirSync(pend).filter(f => f.endsWith('.md')); } catch(e) {}
    if (pending.length === 0) return { answer: 'لا بطاقات معلّقة للنشر.' };
    // decide which pending files to publish
    let take = [];
    if (arg.toLowerCase() === 'all') take = pending;
    else if (pending.includes(arg + '.md')) take = [arg + '.md'];
    else {
      // treat arg as a topic: publish pending cards whose public-topics includes it
      const t = arg.toLowerCase();
      take = pending.filter(f => { try { const m = fs.readFileSync(pend + '/' + f,'utf8').match(/public-topics:\s*\[([^\]]*)\]/i); return m && m[1].toLowerCase().includes(t); } catch(e) { return false; } });
    }
    if (take.length === 0) return { answer: 'لا تطابق: ' + arg + '. المعلّق: ' + pending.map(f=>f.replace('.md','')).join('، ') };
    let done = [];
    for (const f of take) { try { fs.copyFileSync(pend + '/' + f, PUBLIC + '/' + f); fs.unlinkSync(pend + '/' + f); done.push(f.replace('.md','')); } catch(e) {} }
    return { answer: 'نُشرت ' + done.length + ' بطاقة — يراها الضيوف الآن:\n' + done.map(n => '• ' + n).join('\n') };
  }

  // /reject <card> — discard a pending sanitized card
  if (question.toLowerCase().startsWith('/reject')) {
    const name = question.replace(/^\/reject\s*/i, '').trim().replace(/^\[\[|\]\]$/g, '');
    if (!name) return { answer: 'Usage: /reject <اسم-البطاقة>' };
    const src = PUBLIC + '/_pending/' + name + '.md';
    try {
      if (fs.existsSync(src)) fs.unlinkSync(src);
      try { const mf = PUBLIC + '/_pending/_manifest.txt'; const lines = fs.readFileSync(mf,'utf8').split('\n').filter(l => l.trim() && l.trim() !== name); fs.writeFileSync(mf, lines.join('\n') + (lines.length?'\n':'')); } catch(e) {}
      return { answer: '🗑 رُفضت ' + name + ' — لم تُنشر، وتبقى خاصة.' };
    } catch(e) { return { answer: '❌ خطأ: ' + e.message }; }
  }

  // /rescan — trigger build-wiki on new raw/ (مُصنِّف, strong tier on the host)
  if (question.toLowerCase().startsWith('/rescan')) {
    try {
      const r = await this.helpers.httpRequest({ method: 'POST', url: config.build_trigger_url, timeout: 10000 });
      if (r.started) return { answer: '🔄 بدأ بناء الويكي (مُصنِّف). سيظهر الجديد في wiki/ خلال دقائق.' };
      return { answer: 'ℹ️ بناء قيد التشغيل بالفعل — انتظر اكتماله.' };
    } catch(e) {
      return { answer: '❌ تعذّر تشغيل البناء: ' + e.message };
    }
  }

  // /task <text> — add an open task to كاتب's unified store
  if (question.toLowerCase().startsWith('/task')) {
    const txt = question.replace(/^\/task\s*/i, '').trim();
    if (!txt) return { answer: 'Usage: /task <وصف المهمة>' };
    appendToTasks('📌 مهام مفتوحة', '- [ ] ' + txt + ' (أُضيفت ' + new Date().toISOString().split('T')[0] + ')');
    return { answer: '✅ أُضيفت مهمة:\n' + txt + '\n\nستظهر في موجز كاتب.' };
  }

  // /remind <when> <text> — standalone reminder into the unified store (كاتب owns it)
  if (question.toLowerCase().startsWith('/remind')) {
    const body = question.replace(/^\/remind\s*/i, '').trim();
    const iso = body.match(/^(\d{4}-\d{2}-\d{2})/);
    const rel = body.match(/^(\d+)\s*(days?|weeks?|months?|يوم|أيام|[أا]سبوع|[أا]سابيع|شهر|[أا]شهر|شهور)\b/i);
    let date = null, rest = body;
    if (iso) { date = iso[1]; rest = body.slice(iso[0].length).trim(); }
    else if (rel) {
      const amt = parseInt(rel[1]); const u = rel[2].toLowerCase(); const d = new Date();
      if (/week|سبوع|سابيع/.test(u)) d.setDate(d.getDate() + amt * 7);
      else if (/month|شهر|شهور/.test(u)) d.setMonth(d.getMonth() + amt);
      else d.setDate(d.getDate() + amt);
      date = d.toISOString().split('T')[0]; rest = body.slice(rel[0].length).trim();
    }
    if (!rest) return { answer: 'Usage: /remind <3days|2weeks|1month|YYYY-MM-DD> <نص>' };
    appendToTasks('⏰ تذكيرات', '- (' + (date || 'بلا تاريخ') + ') ' + rest);
    return { answer: '⏰ سُجّل تذكير' + (date ? ' (' + date + ')' : '') + ':\n' + rest + '\n\nسيذكّرك به كاتب في موجزه.' };
  }

  // /rules — rules live in MI.md + vault-map.md now (show them)
  if (question.toLowerCase().startsWith('/rules')) {
    let mi = '', vm = '';
    try { mi = fs.readFileSync(KN + '/AIOS/MI.md', 'utf8'); } catch(e) {}
    try { vm = fs.readFileSync(KN + '/AIOS/vault-map.md', 'utf8'); } catch(e) {}
    const laws = (mi.match(/## القوانين العليا[\s\S]*?(?=\n## )/) || [''])[0].slice(0, 1500);
    return { answer: '📋 *القواعد الآن في AIOS/MI.md و AIOS/vault-map.md*\n\n' + (laws || 'افتح AIOS/MI.md') + '\n\n✏️ للتعديل: حرّر الملفين في Obsidian.' };
  }

  // /digest — retired in favor of كاتب's morning/evening briefs
  if (question.toLowerCase().startsWith('/digest')) {
    return { answer: 'ℹ️ الموجز اليومي القديم استُبدل بموجزات كاتب: 🌅 الصباح ٧ص و🌙 المساء ٩م تلقائياً.\n\nاستخدم /task و /remind لإضافة مهام وتذكيرات، وتظهر في الموجز.' };
  }

  // deprecated capture-time recategorization commands (capture is dumb now; مُصنِّف organizes)
  if (question.toLowerCase().startsWith('/tag') || question.toLowerCase().startsWith('/suggest')) {
    return { answer: 'ℹ️ لم يعد التصنيف يدوياً. أرسل الرابط فقط ليُحفظ خاماً، ومُصنِّف يبني البطاقات ويربطها ليلاً (أو /rescan الآن).' };
  }

  if (question.toLowerCase().startsWith('/help')) {
    return { answer: '📖 *الأوامر*\n\n🔗 *الحفظ*\nأرسل رابطاً/صوتاً/صورة ليُحفظ خاماً تلقائياً\n\n❓ *السؤال*\nاسأل بأي لغة: "ماذا أعرف عن X؟" — أجيب من الويكي مع روابط المصادر\n\n🗂 *التصفّح*\n/list — مجالات اللوحة · /list <موضوع> — بطاقات موضوع\n\n📝 *المهام (كاتب)*\n/task <نص> — مهمة جديدة\n/remind <3days|2weeks|YYYY-MM-DD> <نص> — تذكير\nتظهر في موجز الصباح ٧ص والمساء ٩م\n\n🔄 *البناء*\n/rescan — بناء الويكي الآن · /rules — قواعد MI و vault-map\n\n🏗 *المشاريع*\n/research <سؤال> — تقرير فقيه\n/spec <فكرة> — مسودة متطلبات (تعتمدها ثم يبنيها وكيل)\n\n👥 *الضيوف والنشر*\nعلّم بطاقة share: public ثم /publish — الساعي يعقّمها ويعرضها للموافقة\n/approve <بطاقة> · /reject <بطاقة>\n/invite <id> <topics> <duration> · /guests · /revoke <id>' };
  }

  // greetings
  const greetings = ['hi','hello','hey','مرحبا','هلا','السلام','صباح','مساء'];
  if (greetings.some(g => question.toLowerCase().startsWith(g))) {
    return { answer: 'أهلاً! أرسل رابطاً لحفظه، أو اسألني عن شيء تعرفه 👋' };
  }

  // ---- knowledge question → wiki ----
  const r = await answerFromWiki.call(this, question, null);
  if (!r) return { answer: 'الويكي فارغ بعد. أرسل روابط ثم /rescan.' };
  if (!r.answer || /لم أجد|لا توجد معلوم|not found|no .* found/i.test(r.answer) && !r.cards.length) {
    // check raw/inbox for captured-but-unbuilt
    let pending = 0;
    try { pending = fs.readdirSync(KN + '/raw/inbox').filter(f => f.endsWith('.md')).length; } catch(e) {}
    const note = pending ? '\n\n(ملاحظة: ' + pending + ' عنصر ملتقط في raw/inbox لم يُبنَ بعد — جرّب /rescan)' : '';
    return { answer: telegramFormat(r.answer || 'لم أجد شيئاً عن هذا في الويكي.', r.meta || {}) + note, html: true };
  }
  return { answer: telegramFormat(r.answer, r.meta || {}), html: true };
}

// ====================================================
// GUEST  (full layer in Phase 6; here: answer only from _public/)
// ====================================================
const guest = getGuest();
if (!guest) {
  return { answer: 'مرحباً! ليس لديك صلاحية وصول. تواصل مع صاحب البوت.\n\nHello! You do not have access. Contact the bot owner.' };
}
if (question.startsWith('http') || question.startsWith('/')) {
  return { answer: 'الضيوف يسألون فقط عن المحتوى العام.' };
}
const guestGreetings = ['hi','hello','hey','مرحبا','هلا','السلام'];
if (guestGreetings.some(g => question.toLowerCase().startsWith(g))) {
  return { answer: 'أهلاً! اسأل عن المحتوى العام المتاح.' };
}
// answer strictly from _public/, and only cards whose public-topics match this guest's invited topics
const myTopics = (guest.categories || []).map(c => String(c).toLowerCase().trim());
let pubCards = [];
try { pubCards = fs.readdirSync(PUBLIC).filter(f => f.endsWith('.md')); } catch(e) {}
let ctx = '', shown = 0;
for (const f of pubCards) {
  let card = '';
  try { card = fs.readFileSync(PUBLIC + '/' + f, 'utf8'); } catch(e) { continue; }
  const tm = card.match(/public-topics:\s*\[([^\]]*)\]/i);
  const cardTopics = tm ? tm[1].split(',').map(s => s.replace(/['"\s]/g, '').toLowerCase()).filter(Boolean) : [];
  // a guest sees a card only if it is tagged with at least one of their invited topics
  if (!cardTopics.some(t => myTopics.includes(t))) continue;
  ctx += '\n\n=== ' + f.replace('.md','') + ' ===\n' + card.slice(0, 2000);
  shown++;
}
if (shown === 0) return { answer: 'لا يوجد محتوى عام متاح في مواضيعك بعد: ' + myTopics.join('، ') };
const gResp = await this.helpers.httpRequest({
  method: 'POST', url: 'https://api.groq.com/openai/v1/chat/completions',
  headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + config.groq_api_key },
  body: { model: 'llama-3.3-70b-versatile', temperature: 0.3, max_tokens: 600,
    frequency_penalty: 0.6, presence_penalty: 0.3, messages: [
    { role: 'system', content: 'You answer guests on behalf of My Emperor Abdullah. BEGIN every answer by attributing it to him — start with "My Emperor Abdullah knows that…" / "My Emperor Abdullah thinks…" / "My Emperor Abdullah recommends…" (vary the verb: thinks / knows / says / recommends, whatever fits). In Arabic begin with "الإمبراطور عبدالله يرى…" / "يعرف الإمبراطور عبدالله…" / "يوصي الإمبراطور عبدالله…". Answer ONLY from the provided public content — never invent. Reply in the SAME language as the question. Concise: 2-5 sentences, no repetition, no emojis.' },
    { role: 'user', content: ctx.slice(0, 20000) + '\n\nQuestion: ' + question } ]
  }
});
return { answer: gResp.choices?.[0]?.message?.content || 'تعذّر الحصول على إجابة.' };
