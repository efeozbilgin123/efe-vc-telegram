import http from 'node:http';
import crypto from 'node:crypto';
import { AccessToken } from 'livekit-server-sdk';

const { LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET, PORTAL_ROOM_PASSWORD } =
  process.env;
const port = Number(process.env.PORT || 8787);
if (!LIVEKIT_URL || !LIVEKIT_API_KEY || !LIVEKIT_API_SECRET ||
    !PORTAL_ROOM_PASSWORD || PORTAL_ROOM_PASSWORD.length < 12 ||
    !/^wss:\/\//.test(LIVEKIT_URL)) {
  throw new Error('Set LIVEKIT_URL (wss://), LIVEKIT_API_KEY, LIVEKIT_API_SECRET, PORTAL_ROOM_PASSWORD (12+ chars).');
}
const requestCounts = new Map();
const goodName = /^[\p{L}\p{N}_ .-]{1,24}$/u;
const goodRoom = /^[A-Za-z0-9_-]{3,50}$/;

function samePassword(input) {
  const a = Buffer.from(input || '');
  const b = Buffer.from(PORTAL_ROOM_PASSWORD);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

const server = http.createServer(async (req, res) => {
  const reply = (status, data) => {
    res.writeHead(status, {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff'
    });
    res.end(JSON.stringify(data));
  };
  if (req.method === 'GET' && req.url === '/health') {
    return reply(200, { ok: true, service: 'portal-voice-token-server' });
  }
  if (req.method !== 'POST' || req.url !== '/token') {
    return reply(404, { error: 'not_found' });
  }
  const remote = req.socket.remoteAddress || 'unknown';
  const bucket = requestCounts.get(remote) || { count: 0, since: Date.now() };
  if (Date.now() - bucket.since > 60000) {
    bucket.count = 0;
    bucket.since = Date.now();
  }
  bucket.count++;
  requestCounts.set(remote, bucket);
  if (requestCounts.size > 5000) requestCounts.clear();
  if (bucket.count > 20) return reply(429, { error: 'rate_limited' });

  let body = '';
  try {
    for await (const part of req) {
      body += part.toString('utf8');
      if (body.length > 4096) return reply(413, { error: 'too_large' });
    }
    const { room, name, password } = JSON.parse(body);
    if (typeof password !== 'string' || !samePassword(password)) {
      return reply(401, { error: 'invalid_passphrase' });
    }
    if (typeof room !== 'string' || !goodRoom.test(room) ||
        typeof name !== 'string' || !goodName.test(name)) {
      return reply(400, { error: 'invalid_room_or_name' });
    }
    const identity = crypto.randomUUID();
    const token = new AccessToken(LIVEKIT_API_KEY, LIVEKIT_API_SECRET, {
      identity,
      name,
      ttl: '1h'
    });
    token.addGrant({
      roomJoin: true, room: 'portal-' + room,
      canPublish: true, canPublishData: true, canSubscribe: true
    });
    return reply(200, { url: LIVEKIT_URL, token: await token.toJwt() });
  } catch (_) {
    return reply(400, { error: 'bad_request' });
  }
});
server.listen(port, '0.0.0.0', () => {
  console.log('Portal Voice token server listening on ' + port);
});
