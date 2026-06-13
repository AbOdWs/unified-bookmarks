const fs = require('fs');
const config = JSON.parse(fs.readFileSync('/home/node/config.json', 'utf8'));

const result = $('Answer question').item.json;
const answer = (result.answer || '').slice(0, 4096);
const chatId = $('Telegram Trigger').item.json.message.chat.id;
const url = 'https://api.telegram.org/bot' + config.telegram_bot_token + '/sendMessage';

async function send(body) {
  return this.helpers.httpRequest({ method: 'POST', url, headers: { 'Content-Type': 'application/json' }, body });
}

if (result.markdown) {
  try {
    await send.call(this, { chat_id: chatId, text: answer, parse_mode: 'Markdown', disable_web_page_preview: true });
    return { sent: true, mode: 'markdown' };
  } catch(e) {
    // Markdown parse error → resend as plain text (strip link syntax) so the answer never drops
    const plain = answer
      .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')   // [text](url) -> text
      .replace(/\\([_*`\[\]])/g, '$1');           // unescape
    await send.call(this, { chat_id: chatId, text: plain, disable_web_page_preview: true });
    return { sent: true, mode: 'plain-fallback' };
  }
}

await send.call(this, { chat_id: chatId, text: answer });
return { sent: true, mode: 'plain' };
