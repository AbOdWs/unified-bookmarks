const fs = require('fs');
const config = JSON.parse(fs.readFileSync('/home/node/config.json', 'utf8'));

const result = $('Answer question').item.json;
const answer = (result.answer || '').slice(0, 4096);
const chatId = $('Telegram Trigger').item.json.message.chat.id;
const url = 'https://api.telegram.org/bot' + config.telegram_bot_token + '/sendMessage';

async function send(body) {
  return this.helpers.httpRequest({ method: 'POST', url, headers: { 'Content-Type': 'application/json' }, body });
}

if (result.html) {
  try {
    await send.call(this, { chat_id: chatId, text: answer, parse_mode: 'HTML', disable_web_page_preview: true });
    return { sent: true, mode: 'html' };
  } catch(e) {
    // HTML parse error → strip tags and resend as plain text so the answer never drops
    const plain = answer
      .replace(/<blockquote[^>]*>/gi, '').replace(/<\/blockquote>/gi, '')
      .replace(/<a href="([^"]+)">([^<]*)<\/a>/gi, '$2 ($1)')
      .replace(/<[^>]+>/g, '')
      .replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>');
    await send.call(this, { chat_id: chatId, text: plain, disable_web_page_preview: true });
    return { sent: true, mode: 'plain-fallback' };
  }
}

await send.call(this, { chat_id: chatId, text: answer });
return { sent: true, mode: 'plain' };
