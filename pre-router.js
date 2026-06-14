const fs = require('fs');
const message = $('Telegram Trigger').item.json.message;
const text = (message.text || '').trim();

const isCommand = text.startsWith('/tag') ||
                  text.startsWith('/rules') ||
                  text.startsWith('/rescan') ||
                  text.startsWith('/list');

// ناظم routing log — append-only, reviewable record of every message + its initial route.
// (Foundation for diagnosing conversation/routing quality; صنّاع reviews it periodically.)
try {
  let route;
  if (message.voice || message.audio) route = 'capture:voice';
  else if (message.photo || (message.document && message.document.mime_type && message.document.mime_type.startsWith('image'))) route = 'capture:image';
  else if (/^https?:\/\//.test(text)) route = 'capture:link';
  else if (text.startsWith('/')) route = 'command:' + text.split(/\s/)[0];
  else if (text) route = 'question';
  else route = 'other';
  const dir = '/home/node/knowledge/AIOS/history';
  fs.mkdirSync(dir, { recursive: true });
  fs.appendFileSync(dir + '/routing-log.jsonl',
    JSON.stringify({ t: new Date().toISOString(), chat: String(message.chat && message.chat.id || ''), route, text: text.slice(0, 120) }) + '\n', 'utf8');
} catch(e) {}

return {
  message,
  text,
  isCommand
};
