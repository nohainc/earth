import tls from 'node:tls';

export async function sendTestEmail({ smtpUser, appPassword, from, to, subject, text, html }) {
  return new Promise((resolve, reject) => {
    const socket = tls.connect({ host: 'smtp.gmail.com', port: 465, timeout: 10000 }, () => {
      console.log('Connected to smtp.gmail.com:465 via TLS');
    });

    let buffer = '';
    let step = 0;

    socket.on('data', (data) => {
      const msg = data.toString();
      buffer += msg;
      console.log('<<< ' + msg.trim());

      if (step === 0 && msg.startsWith('220')) {
        step = 1;
        send('EHLO localhost');
      } else if (step === 1 && msg.startsWith('250')) {
        step = 2;
        send('AUTH LOGIN');
      } else if (step === 2 && msg.startsWith('334')) {
        step = 3;
        send(Buffer.from(smtpUser).toString('base64'));
      } else if (step === 3 && msg.startsWith('334')) {
        step = 4;
        send(Buffer.from(appPassword.replace(/\s+/g, '')).toString('base64'));
      } else if (step === 4 && msg.startsWith('235')) {
        step = 5;
        console.log('*** SMTP Authentication Successful! ***');
        send(`MAIL FROM:<${from}>`);
      } else if (step === 5 && msg.startsWith('250')) {
        step = 6;
        send(`RCPT TO:<${to}>`);
      } else if (step === 6 && msg.startsWith('250')) {
        step = 7;
        send('DATA');
      } else if (step === 7 && msg.startsWith('354')) {
        step = 8;
        const date = new Date().toUTCString();
        const body = html || text;
        const contentType = html ? 'text/html' : 'text/plain';
        const message = [
          `Date: ${date}`,
          `From: EARTH Identity <${from}>`,
          `To: ${to}`,
          `Subject: ${subject}`,
          'MIME-Version: 1.0',
          `Content-Type: ${contentType}; charset=utf-8`,
          '',
          body,
          '.',
        ].join('\r\n');
        send(message);
      } else if (step === 8 && msg.startsWith('250')) {
        console.log('*** Email accepted by Gmail for delivery! ***');
        send('QUIT');
        socket.end();
        resolve(true);
      } else if (msg.startsWith('5') || msg.startsWith('4')) {
        reject(new Error('SMTP Error: ' + msg.trim()));
      }
    });

    function send(cmd) {
      console.log('>>> ' + (cmd.length > 50 ? `${cmd.slice(0, 50)}...` : cmd));
      socket.write(`${cmd}\r\n`);
    }

    socket.on('error', reject);
  });
}

const pass = process.env.GMAIL_APP_PASSWORD || process.argv[2];
const to = process.argv[3] || 'vitalii.noga@gmail.com';

if (!pass) {
  console.log('Usage: GMAIL_APP_PASSWORD="your_password" node scripts/test-smtp-email.mjs');
  console.log('Or: node scripts/test-smtp-email.mjs <app-password> <recipient-email>');
  process.exit(0);
}

console.log('Sending test email to ' + to + ' using sender earth@nohainc.com...');
try {
  await sendTestEmail({
    smtpUser: 'vitalii@nohainc.com',
    appPassword: pass,
    from: 'earth@nohainc.com',
    to,
    subject: 'EARTH Identity - Test Verification Email',
    text: 'This is a test email from EARTH Identity using your Gmail SMTP configuration.',
    html: '<p>Hello Vitalii,</p><p>This is a test email from <strong>EARTH Identity</strong> (<code>earth@nohainc.com</code>) sent via direct SMTPS socket integration.</p><p>If you see this, email sending is working!</p>',
  });
  console.log('SUCCESS! Test email sent successfully.');
} catch (e) {
  console.error('FAILED to send email:', e.message);
}
