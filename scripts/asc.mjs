// App Store Connect API helper: node scripts/asc.mjs <METHOD> <path> [json-body]
// Reads ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH from .env.local (gitignored; key file lives outside the repo).
import { createSign } from 'node:crypto';
import { readFileSync } from 'node:fs';
const env = Object.fromEntries(readFileSync(new URL('../.env.local', import.meta.url), 'utf8').split('\n')
  .filter(l => /^ASC_/.test(l)).map(l => l.split('=').map(s => s.trim())));
const b = o => Buffer.from(JSON.stringify(o)).toString('base64url');
const n = Math.floor(Date.now() / 1000);
const h = b({ alg: 'ES256', kid: env.ASC_KEY_ID, typ: 'JWT' }), p = b({ iss: env.ASC_ISSUER_ID, iat: n, exp: n + 900, aud: 'appstoreconnect-v1' });
const s = createSign('SHA256'); s.update(`${h}.${p}`);
const jwt = `${h}.${p}.${s.sign({ key: readFileSync(env.ASC_KEY_PATH), dsaEncoding: 'ieee-p1363' }).toString('base64url')}`;
const [method, path, body] = process.argv.slice(2);
const r = await fetch('https://api.appstoreconnect.apple.com' + path, { method, body,
  headers: { Authorization: `Bearer ${jwt}`, 'Content-Type': 'application/json' } });
const t = await r.text();
console.log(r.status, t.length > 6000 ? t.slice(0, 6000) + '…' : t);
