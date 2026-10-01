// Replace one App Store screenshot by file name, keeping its position: node scripts/asc-swap-shot.mjs <setId> <fileName> <newPath>
import { execFileSync } from 'node:child_process';
import { readFileSync, statSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { basename } from 'node:path';
const [setId, name, path] = process.argv.slice(2);
const asc = (m, p, b) => {
  const out = execFileSync('node', ['scripts/asc.mjs', m, p, ...(b ? [JSON.stringify(b)] : [])]).toString();
  const i = out.indexOf(' '); return { status: +out.slice(0, i), json: out.slice(i + 1).trim() ? JSON.parse(out.slice(i + 1)) : null };
};
const list = asc('GET', `/v1/appScreenshotSets/${setId}/appScreenshots`).json.data;
const order = list.map(s => s.id);
const old = list.find(s => s.attributes.fileName === name);
if (!old) { console.log('not found', list.map(s => s.attributes.fileName)); process.exit(1); }
const pos = order.indexOf(old.id);
const data = readFileSync(path);
const r = asc('POST', '/v1/appScreenshots', { data: { type: 'appScreenshots', attributes: { fileName: basename(path), fileSize: statSync(path).size },
  relationships: { appScreenshotSet: { data: { type: 'appScreenshotSets', id: setId } } } } }).json.data;
for (const op of r.attributes.uploadOperations) {
  const chunk = data.subarray(op.offset, op.offset + op.length);
  const res = await fetch(op.url, { method: op.method, body: chunk, headers: Object.fromEntries(op.requestHeaders.map(h => [h.name, h.value])) });
  if (!res.ok) { console.log('upload failed', res.status); process.exit(1); }
}
const md5 = createHash('md5').update(data).digest('hex');
console.log('commit', asc('PATCH', `/v1/appScreenshots/${r.id}`, { data: { type: 'appScreenshots', id: r.id, attributes: { uploaded: true, sourceFileChecksum: md5 } } }).status);
console.log('delete old', asc('DELETE', `/v1/appScreenshots/${old.id}`).status);
order[pos] = r.id;
console.log('reorder', asc('PATCH', `/v1/appScreenshotSets/${setId}/relationships/appScreenshots`, { data: order.map(id => ({ type: 'appScreenshots', id })) }).status);
