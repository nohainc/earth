import { connect } from 'cloudflare:sockets';

export interface SmtpEmailOptions {
  to: string;
  from: string;
  subject: string;
  text: string;
  html?: string;
  smtpUser: string;
  gmailAppPassword: string;
}

export async function sendSmtpEmail(options: SmtpEmailOptions): Promise<{ messageId: string }> {
  const { to, from, subject, text, html, smtpUser, gmailAppPassword } = options;
  const host = 'smtp.gmail.com';
  const port = 465; // Direct TLS SMTPS

  const socket = connect({ hostname: host, port }, { secureTransport: 'on' });
  const writer = socket.writable.getWriter();
  const reader = socket.readable.getReader();
  const decoder = new TextDecoder();
  const encoder = new TextEncoder();

  async function send(cmd: string) {
    await writer.write(encoder.encode(`${cmd}\r\n`));
  }

  async function receive() {
    const { value } = await reader.read();
    return value ? decoder.decode(value) : '';
  }

  try {
    // 220 greeting
    await receive();

    // EHLO
    await send('EHLO localhost');
    await receive();

    // AUTH LOGIN
    await send('AUTH LOGIN');
    await receive();

    await send(btoa(smtpUser));
    await receive();

    await send(btoa(gmailAppPassword.replace(/\s+/g, '')));
    const authRes = await receive();
    if (!authRes.startsWith('235')) {
      throw new Error(`SMTP Authentication failed: ${authRes.trim()}`);
    }

    // MAIL FROM
    await send(`MAIL FROM:<${from}>`);
    await receive();

    // RCPT TO
    await send(`RCPT TO:<${to}>`);
    await receive();

    // DATA
    await send('DATA');
    await receive();

    const date = new Date().toUTCString();
    const messageId = `<${crypto.randomUUID()}@auth.earthuc.com>`;
    const contentType = html ? 'text/html' : 'text/plain';
    const body = html || text;

    const message = [
      `Date: ${date}`,
      `Message-ID: ${messageId}`,
      `From: EARTH Identity <${from}>`,
      `To: ${to}`,
      `Subject: ${subject}`,
      'MIME-Version: 1.0',
      `Content-Type: ${contentType}; charset=utf-8`,
      'Content-Transfer-Encoding: 7bit',
      '',
      body,
      '.',
    ].join('\r\n');

    await send(message);
    await receive();

    // QUIT
    await send('QUIT');
    await socket.close();

    return { messageId };
  } catch (e) {
    try {
      await socket.close();
    } catch {}
    throw e;
  }
}
