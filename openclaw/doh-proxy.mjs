/**
 * GlibClaw — DoH Proxy
 */

import dgram from 'dgram';

const DOH_PORT = parseInt(process.env.DOH_PORT || '5300');
const DOH_UPSTREAM = process.env.DOH_UPSTREAM || 'https://8.8.8.8/dns-query';
const TIMEOUT_MS = parseInt(process.env.DOH_TIMEOUT || '5000');

const server = dgram.createSocket('udp4');

server.on('message', async (msg, rinfo) => {
  try {
    const b64 = msg.toString('base64url');
    const res = await fetch(`${DOH_UPSTREAM}?dns=${b64}`, {
      headers: { accept: 'application/dns-message' },
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });

    if (!res.ok) return;

    const buf = Buffer.from(await res.arrayBuffer());
    server.send(buf, rinfo.port, rinfo.address);
  } catch {}
});

server.on('error', (e) => {
  process.stderr.write(`[doh-proxy] fatal: ${e.message}\n`);
  process.exit(1);
});

server.bind(DOH_PORT, '127.0.0.1', () => {
  process.stdout.write(`[doh-proxy] listening on 127.0.0.1:${DOH_PORT} → ${DOH_UPSTREAM}\n`);
});
