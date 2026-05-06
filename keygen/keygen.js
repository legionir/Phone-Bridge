// keygen/keygen.js
// ابزار تولید رشته رمزگذاری شده برای Bridge app
// اجرا: node keygen.js

import crypto from 'crypto';
import readline from 'readline';

// کلید باید دقیقاً همان کلید داخل برنامه Flutter باشد
const KEY = Buffer.from([
  0x42, 0x72, 0x69, 0x64, 0x67, 0x65, 0x41, 0x70,
  0x70, 0x4B, 0x65, 0x79, 0x32, 0x30, 0x32, 0x34,
  0x53, 0x65, 0x63, 0x72, 0x65, 0x74, 0x58, 0x59,
  0x5A, 0x21, 0x40, 0x23, 0x24, 0x25, 0x5E, 0x26,
]);

/**
 * رمزگذاری config با AES-256-CBC
 * فرمت خروجی: base64( IV[16] + ciphertext )
 */
function encrypt(data) {
  const json = JSON.stringify(data);
  const iv = crypto.randomBytes(16);
  const cipher = crypto.createCipheriv('aes-256-cbc', KEY, iv);
  const encrypted = Buffer.concat([
    cipher.update(json, 'utf8'),
    cipher.final(),
  ]);
  const combined = Buffer.concat([iv, encrypted]);
  return combined.toString('base64');
}

/**
 * رمزگشایی برای تأیید صحت
 */
function decrypt(encoded) {
  try {
    const raw = Buffer.from(encoded, 'base64');
    const iv = raw.subarray(0, 16);
    const ciphertext = raw.subarray(16);
    const decipher = crypto.createDecipheriv('aes-256-cbc', KEY, iv);
    const plain = Buffer.concat([
      decipher.update(ciphertext),
      decipher.final(),
    ]);
    return JSON.parse(plain.toString('utf8'));
  } catch (e) {
    return null;
  }
}

function prompt(rl, question) {
  return new Promise((resolve) => {
    rl.question(question, (answer) => resolve(answer.trim()));
  });
}

async function main() {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  console.log('\n╔══════════════════════════════════════╗');
  console.log('║     Bridge App - Config Keygen       ║');
  console.log('╚══════════════════════════════════════╝\n');

  // حالت‌های مختلف
  console.log('1. Generate new config string');
  console.log('2. Verify existing config string');
  console.log('3. Decode existing config string\n');

  const mode = await prompt(rl, 'Choose mode (1/2/3): ');

  if (mode === '2' || mode === '3') {
    const encoded = await prompt(rl, 'Enter base64 config string: ');
    const decoded = decrypt(encoded);
    if (!decoded) {
      console.log('\n❌ Invalid or corrupted config string.');
    } else {
      console.log('\n✅ Valid config string!');
      if (mode === '3') {
        console.log('\nDecoded config:');
        console.log(JSON.stringify(decoded, null, 2));
      }
    }
    rl.close();
    return;
  }

  // حالت ۱: تولید config جدید
  console.log('\n--- Enter connection details ---\n');

  const serverHost = await prompt(rl, 'Server host (e.g. example.com): ');
  if (!serverHost) {
    console.log('❌ Server host is required.');
    rl.close();
    return;
  }

  const serverPortStr = await prompt(rl, 'Server port (default: 443): ');
  const serverPort = parseInt(serverPortStr) || 443;
  if (serverPort < 1 || serverPort > 65535) {
    console.log('❌ Invalid port number.');
    rl.close();
    return;
  }

  const wsPath = await prompt(rl, 'WebSocket path (default: /api/bridge): ');
  const finalWsPath = wsPath || '/api/bridge';

  const isSSLStr = await prompt(rl, 'Use SSL/TLS? wss:// (Y/n): ');
  const isSSL = isSSLStr.toLowerCase() !== 'n';

  const config = {
    serverHost,
    serverPort,
    wsPath: finalWsPath,
    isSSL,
  };

  console.log('\n--- Config to encrypt ---');
  console.log(JSON.stringify(config, null, 2));

  const confirmStr = await prompt(rl, '\nConfirm and generate? (Y/n): ');
  if (confirmStr.toLowerCase() === 'n') {
    console.log('Cancelled.');
    rl.close();
    return;
  }

  const encoded = encrypt(config);

  console.log('\n╔══════════════════════════════════════╗');
  console.log('║         ENCRYPTED CONFIG STRING      ║');
  console.log('╚══════════════════════════════════════╝\n');
  console.log(encoded);
  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  // تأیید رمزگشایی
  const verified = decrypt(encoded);
  if (verified) {
    console.log('✅ Verification passed — config is valid.\n');
    const scheme = isSSL ? 'wss' : 'ws';
    console.log(
      `🔗 WebSocket URL: ${scheme}://${serverHost}:${serverPort}${finalWsPath}`
    );
  } else {
    console.log('❌ Verification failed!');
  }

  console.log('\n📋 Copy the string above and paste into the app Settings.');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  rl.close();
}

main().catch(console.error);