'use strict';
/*
 * WebSocket lobby/signaling endpoint for the browser build.
 * It exchanges room lists, accounts, SDP offers/answers and ICE candidates.
 * Gameplay packets never pass through this process: browsers connect directly
 * over WebRTC after the handshake.
 *
 * Run on the build host with:
 *   SIGNAL_HOST=172.17.0.1 SIGNAL_PORT=8899 node server/lan_signal_server.js
 */
let WebSocketServer;
try {
  ({ WebSocketServer } = require('ws'));
} catch (_) {
  ({ WebSocketServer } = require('/home/admin/mirugumi.space/node_modules/ws'));
}

const crypto = require('crypto');
const fs = require('fs');
const HOST = process.env.SIGNAL_HOST || '172.17.0.1';
const PORT = Number(process.env.SIGNAL_PORT || 8899);
const DATA_DIR = '/home/admin/duel-signal';
const ACCOUNTS_FILE = DATA_DIR + '/accounts.json';
const GRACE_MS = Number(process.env.SIGNAL_GRACE_MS || 60000);
const rooms = new Map();
const sockets = new Set();
const accounts = new Map();
let roomSerial = 0;

try {
  const saved = JSON.parse(fs.readFileSync(ACCOUNTS_FILE, 'utf8'));
  if (saved && typeof saved === 'object') {
    for (const [name, record] of Object.entries(saved)) {
      if (record && typeof record === 'object') {
        accounts.set(name, {
          question: String(record.question || '').slice(0, 40),
          answerHash: String(record.answerHash || ''),
          wins: Number(record.wins) || 0,
          losses: Number(record.losses) || 0,
        });
      }
    }
  }
} catch (_) {}

function answerHash(name, answer) {
  return crypto.createHash('sha256').update(name + '\n' + String(answer || '')).digest('hex');
}

function saveAccounts() {
  try {
    fs.writeFileSync(ACCOUNTS_FILE + '.tmp', JSON.stringify(Object.fromEntries(accounts)));
    fs.renameSync(ACCOUNTS_FILE + '.tmp', ACCOUNTS_FILE);
  } catch (_) {}
}

function ensureAccount(name) {
  let account = accounts.get(name);
  if (!account) {
    account = { question: '', answerHash: '', wins: 0, losses: 0 };
    accounts.set(name, account);
  }
  return account;
}

function leaderboardRows() {
  return [...accounts.entries()]
    .filter(([, record]) => record.wins + record.losses > 0)
    .map(([name, record]) => ({ name, wins: record.wins, losses: record.losses }))
    .sort((a, b) => (b.wins - a.wins) || (a.losses - b.losses) || a.name.localeCompare(b.name))
    .slice(0, 20);
}

function sendLeaderboard(ws) {
  send(ws, { type: 'leaderboard', entries: leaderboardRows() });
}

function broadcastLeaderboard() {
  for (const ws of sockets) {
    if (ws.readyState === 1) sendLeaderboard(ws);
  }
}

function text(value, fallback, max) {
  const result = String(value == null ? '' : value).trim().slice(0, max || 16);
  return result || fallback;
}

function send(ws, message) {
  if (ws && ws.readyState === 1) ws.send(JSON.stringify(message));
}

function roomOf(ws) {
  return ws.roomKey ? rooms.get(ws.roomKey) : null;
}

function publicRooms(excludeKey) {
  const list = [];
  for (const [key, room] of rooms) {
    const guest = room.guest;
    const hostOnline = !!(room.host && room.host.ws);
    const guestOnline = !!(guest && guest.ws);
    let status = 'waiting';
    if (guest) status = guestOnline && hostOnline ? 'playing' : 'reconnecting';
    else if (!hostOnline) status = 'reconnecting';
    list.push({
      key,
      name: room.name,
      host: room.host.name,
      guest: guest ? guest.name : '',
      status,
      players: guest ? 2 : 1,
      joinable: !guest && hostOnline,
      mine: key === excludeKey,
    });
  }
  return list;
}

function broadcastRooms() {
  for (const ws of sockets) {
    if (ws.readyState !== 1) continue;
    send(ws, { type: 'rooms', rooms: publicRooms(ws.roomKey) });
  }
}

function slotOf(room, role) {
  return role === 'host' ? room.host : room.guest;
}

function purgeRoom(room) {
  if (room.purgeTimer) {
    clearTimeout(room.purgeTimer);
    room.purgeTimer = null;
  }
  if (!rooms.has(room.key)) return;
  rooms.delete(room.key);
  const host = room.host.ws;
  const guest = room.guest ? room.guest.ws : null;
  const done = (ws, reason) => {
    if (!ws) return;
    ws.roomKey = null;
    ws.role = null;
    send(ws, { type: 'session_closed', reason });
  };
  done(host, '对手已离开房间');
  done(guest, '房主已关闭房间');
  broadcastRooms();
}

// 信令掉线时先保留房间，给掉线的一方留出重连窗口；超时才真正结束。
function detach(ws, immediate) {
  const room = roomOf(ws);
  if (room) {
    const role = ws.role;
    const slot = slotOf(room, role);
    if (slot && slot.ws === ws) slot.ws = null;
    const other = slotOf(room, role === 'host' ? 'guest' : 'host');
    if (other && other.ws) send(other.ws, { type: 'peer_offline', role });
    if (immediate) {
      purgeRoom(room);
    } else if (room.host.ws || (room.guest && room.guest.ws)) {
      // 还有一方在线，等宽限期结束再收尾
      if (room.purgeTimer) clearTimeout(room.purgeTimer);
      room.purgeTimer = setTimeout(() => purgeRoom(room), GRACE_MS);
    } else {
      purgeRoom(room);
    }
  }
  ws.roomKey = null;
  ws.role = null;
  broadcastRooms();
}

function authOk(ws, name, account) {
  send(ws, {
    type: 'auth_ok',
    name,
    question: account.question,
    wins: account.wins,
    losses: account.losses,
  });
  sendLeaderboard(ws);
}

const wss = new WebSocketServer({ host: HOST, port: PORT, maxPayload: 256 * 1024 });

wss.on('connection', (ws) => {
  ws.isAlive = true;
  sockets.add(ws);
  send(ws, { type: 'rooms', rooms: publicRooms(null) });
  sendLeaderboard(ws);

  ws.on('pong', () => { ws.isAlive = true; });
  ws.on('message', (raw) => {
    let message;
    try {
      message = JSON.parse(raw.toString('utf8'));
    } catch (_) {
      return;
    }
    if (process.env.SIGNAL_DEBUG) {
      var extra = message.type === 'ice' ? JSON.stringify(message.candidate) : (message.room || '');
      console.log('[msg]', ws.role || '-', ws.name || '-', message.type, extra);
    }
    if (!message || typeof message.type !== 'string') return;

    if (message.type === 'hello') {
      ws.name = text(message.name, '玩家');
      send(ws, { type: 'rooms', rooms: publicRooms(ws.roomKey) });
      return;
    }

    if (message.type === 'register') {
      const name = text(message.name, '', 16);
      const question = text(message.question, '', 40);
      const answer = text(message.answer, '', 40);
      if (!name || !question || !answer) {
        send(ws, { type: 'auth_error', message: '用户名、登录问题和答案都需要填写' });
        return;
      }
      let account = accounts.get(name);
      if (account && account.question) {
        send(ws, { type: 'auth_error', message: '用户名已被注册，请改用登录' });
        return;
      }
      if (!account) {
        account = { question: '', answerHash: '', wins: 0, losses: 0 };
      }
      // Accounts created only by match results have no question yet; let the
      // owner claim that name by registering a security question once.
      account.question = question;
      account.answerHash = answerHash(name, answer);
      accounts.set(name, account);
      saveAccounts();
      authOk(ws, name, account);
      broadcastLeaderboard();
      return;
    }

    if (message.type === 'login_begin') {
      const name = text(message.name, '', 16);
      const account = accounts.get(name);
      if (!account) {
        send(ws, { type: 'auth_error', message: '用户名不存在，请先注册' });
        return;
      }
      if (!account.question) {
        send(ws, { type: 'auth_error', message: '该用户名没有设置登录问题' });
        return;
      }
      send(ws, { type: 'auth_question', name, question: account.question });
      return;
    }

    if (message.type === 'login_answer') {
      const name = text(message.name, '', 16);
      const answer = text(message.answer, '', 40);
      const account = accounts.get(name);
      if (!account) {
        send(ws, { type: 'auth_error', message: '用户名不存在，请先注册' });
        return;
      }
      if (answerHash(name, answer) !== account.answerHash) {
        send(ws, { type: 'auth_error', message: '答案不正确' });
        return;
      }
      authOk(ws, name, account);
      return;
    }

    if (message.type === 'create') {
      if (ws.roomKey) {
        send(ws, { type: 'error', message: '已在房间中' });
        return;
      }
      const key = text(message.room, '房间' + (++roomSerial), 32);
      if (rooms.has(key)) {
        send(ws, { type: 'error', message: '房间名已被占用，请换一个' });
        return;
      }
      const name = text(message.name || ws.name, '房主');
      const room = { key, name: key, host: { ws, name }, guest: null };
      rooms.set(key, room);
      ws.roomKey = key;
      ws.role = 'host';
      ws.name = name;
      send(ws, { type: 'created', room: key });
      broadcastRooms();
      return;
    }

    if (message.type === 'join') {
      if (ws.roomKey) {
        send(ws, { type: 'error', message: '已在房间中' });
        return;
      }
      const key = text(message.room, '', 32);
      const room = rooms.get(key);
      if (!room) {
        send(ws, { type: 'error', message: '房间不存在，可能已结束' });
        return;
      }
      if (room.guest) {
        send(ws, { type: 'error', message: '房间已满' });
        return;
      }
      ws.name = text(message.name || ws.name, '玩家');
      room.guest = { ws, name: ws.name };
      ws.roomKey = key;
      ws.role = 'guest';
      send(room.host.ws, { type: 'peer_joined', name: ws.name });
      send(ws, { type: 'joined', room: key, host: room.host.name });
      broadcastRooms();
      return;
    }

    if (message.type === 'rejoin') {
      const key = text(message.room, '', 32);
      const room = rooms.get(key);
      if (!room) {
        send(ws, { type: 'error', message: '房间已结束' });
        return;
      }
      const role = message.role === 'guest' ? 'guest' : 'host';
      const slot = slotOf(room, role);
      if (!slot) {
        send(ws, { type: 'error', message: '房间已结束' });
        return;
      }
      if (slot.ws) {
        send(ws, { type: 'error', message: '该席位已被占用' });
        return;
      }
      slot.ws = ws;
      ws.roomKey = key;
      ws.role = role;
      ws.name = slot.name;
      if (room.purgeTimer) {
        clearTimeout(room.purgeTimer);
        room.purgeTimer = null;
      }
      send(ws, { type: 'rejoined', room: key, role: role, host: room.host.name });
      const other = slotOf(room, role === 'host' ? 'guest' : 'host');
      if (other && other.ws) send(other.ws, { type: 'peer_back', role: role });
      broadcastRooms();
      return;
    }

    if (message.type === 'offer' || message.type === 'answer' || message.type === 'ice') {
      const room = roomOf(ws);
      if (!room) return;
      const target = ws.role === 'host' ? room.guest : room.host;
      if (target) send(target.ws, message);
      return;
    }

    if (message.type === 'result') {
      const room = roomOf(ws);
      if (!room || ws.role !== 'host' || !room.guest) return;
      const winner = message.winner_role === 'guest' ? room.guest.name : room.host.name;
      const loser = message.winner_role === 'guest' ? room.host.name : room.guest.name;
      if (!winner || !loser || winner === loser) return;
      ensureAccount(winner).wins += 1;
      ensureAccount(loser).losses += 1;
      saveAccounts();
      broadcastLeaderboard();
      return;
    }

    if (message.type === 'leave') {
      detach(ws, true);
      ws.close();
      return;
    }

    if (message.type === 'ping') {
      send(ws, { type: 'pong' });
    }
  });

  ws.on('close', () => {
    sockets.delete(ws);
    detach(ws);
  });
  ws.on('error', () => {
    sockets.delete(ws);
    detach(ws);
  });
});

setInterval(() => {
  for (const ws of sockets) {
    if (ws.isAlive === false) {
      ws.terminate();
      continue;
    }
    ws.isAlive = false;
    try { ws.ping(); } catch (_) {}
  }
}, 30000);

console.log('duel signal listening on ' + HOST + ':' + PORT);
