// Holt den öffentlichen iCloud-Kalender und legt ihn verschlüsselt als calendar.enc.json ab.
// Benötigt die Repo-Secrets ICAL_URL (webcal://… oder https://…) und FAMILY_KEY (Schlüssel aus dem App-Link).
import { readFile, writeFile } from 'node:fs/promises';
import { createCipheriv, createHmac, pbkdf2Sync, randomBytes } from 'node:crypto';

const url = (process.env.ICAL_URL || '').trim().replace(/^webcal:\/\//i, 'https://');
const pass = (process.env.FAMILY_KEY || '').trim();
if (!url || !pass) {
  console.error('ICAL_URL oder FAMILY_KEY fehlt in den Repo-Secrets.');
  process.exit(1);
}

const res = await fetch(url, { headers: { 'User-Agent': 'familienzeit-calendar-sync' } });
if (!res.ok) {
  console.error(`Kalender-Abruf fehlgeschlagen: HTTP ${res.status}`);
  process.exit(1);
}
const ics = await res.text();
if (!ics.includes('BEGIN:VCALENDAR')) {
  console.error('Die Antwort ist kein Kalender (BEGIN:VCALENDAR fehlt).');
  process.exit(1);
}

// Nur neu schreiben, wenn sich der Kalender wirklich geändert hat.
const fingerprint = createHmac('sha256', pass).update(ics).digest('hex');
try {
  const old = JSON.parse(await readFile('calendar.enc.json', 'utf8'));
  if (old.fp === fingerprint) {
    console.log('Kalender unverändert.');
    process.exit(0);
  }
} catch {}

const iter = 200000;
const salt = randomBytes(16);
const iv = randomBytes(12);
const key = pbkdf2Sync(pass, salt, iter, 32, 'sha256');
const cipher = createCipheriv('aes-256-gcm', key, iv);
const data = Buffer.concat([cipher.update(ics, 'utf8'), cipher.final(), cipher.getAuthTag()]);

await writeFile('calendar.enc.json', JSON.stringify({
  v: 1,
  updated: new Date().toISOString(),
  iter,
  salt: salt.toString('base64'),
  iv: iv.toString('base64'),
  fp: fingerprint,
  data: data.toString('base64'),
}) + '\n');
console.log(`Kalender aktualisiert (${ics.length} Zeichen).`);
