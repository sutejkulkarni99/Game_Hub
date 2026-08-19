const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const partyJo = require('./gameLogic');
const tambola = require('./tambolaLogic');

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
    cors: { origin: "*", methods: ["GET", "POST"] },
    transports: ['websocket', 'polling']
});

const PORT = process.env.PORT || 8085;
app.use(express.static('public'));

app.get('/', (req, res) => res.sendFile(__dirname + '/public/index.html'));
app.get('/partyjo', (req, res) => res.sendFile(__dirname + '/public/partyjo.html'));
app.get('/tambola', (req, res) => res.sendFile(__dirname + '/public/tambola.html'));

// ==================== PARTY JO NAMESPACE ====================
const pjNsp = io.of('/partyjo');
const pjDisconnectTimers = {};

function getPjTimerKey(roomCode, playerName) {
    return `pj_${roomCode}_${playerName}`;
}

pjNsp.on('connection', (socket) => {
    console.log(`[PARTYJO] ${socket.id}`);
    let currentRoom = null;

    socket.on('create_room', ({ name, emoji, roomName }) => {
        if (!name || name.trim().length === 0) return socket.emit('error', 'Name required');
        name = name.trim();
        if (name.length > 20) return socket.emit('error', 'Name too long');
        const code = Math.floor(1000 + Math.random() * 9000).toString();
        const chosenEmoji = emoji || partyJo.EMOJIS[Math.floor(Math.random() * partyJo.EMOJIS.length)];
        const room = partyJo.createRoom(code, socket.id, name, roomName || '', chosenEmoji);
        if (!room) return socket.emit('error', 'Creation failed');
        socket.join(code);
        currentRoom = code;
        pjNsp.to(code).emit('state', room);
    });

    socket.on('join_room', ({ code, name, emoji }) => {
        if (!name || !code) return socket.emit('error', 'Invalid');
        name = name.trim();
        let room = partyJo.getRoom(code);
        if (!room) return socket.emit('error', 'Room not found');

        if (room.gamePhase !== 'LOBBY') {
            const result = partyJo.reconnectPlayer(code, socket.id, name);
            if (result) {
                socket.join(code);
                currentRoom = code;
                const key = getPjTimerKey(code, result.oldId ? partyJo.getRoom(code).players[result.oldId]?.name : name);
                if (pjDisconnectTimers[key]) { clearTimeout(pjDisconnectTimers[key]); delete pjDisconnectTimers[key]; }
                pjNsp.to(code).emit('announcement', `🔄 ${name} reconnected!`);
                if (result.penalty > 0) pjNsp.to(code).emit('announcement', `⚠️ Rejoin penalty of +${result.penalty} applied to ${name}`);
                pjNsp.to(code).emit('state', result.room);
                return;
            }
            if (room.gamePhase === 'ROUND_OVER') {
                const rejoin = partyJo.rejoinAfterKick(code, socket.id, name, emoji);
                if (rejoin) {
                    socket.join(code);
                    currentRoom = code;
                    pjNsp.to(code).emit('announcement', `🔄 ${name} rejoined (+${rejoin.penalty} penalty)`);
                    pjNsp.to(code).emit('state', rejoin.room);
                    return;
                }
            }
            return socket.emit('error', 'Cannot rejoin');
        }

        const chosenEmoji = emoji || partyJo.EMOJIS[Math.floor(Math.random() * partyJo.EMOJIS.length)];
        room = partyJo.joinRoom(code, socket.id, name, chosenEmoji);
        if (!room) return socket.emit('error', 'Room full/name taken');
        socket.join(code);
        currentRoom = code;
        pjNsp.to(code).emit('state', room);
    });

    socket.on('get_available_rooms', () => socket.emit('available_rooms', partyJo.getAvailableRooms()));
    socket.on('get_room_players', (code) => {
        const info = partyJo.getRoomPlayersByCode(code);
        socket.emit('room_players', info);
    });

    socket.on('update_settings', ({ code, settings }) => {
        const room = partyJo.getRoom(code);
        if (!room || room.hostId !== socket.id) return;
        partyJo.updateSettings(code, settings);
        pjNsp.to(code).emit('state', room);
    });

    socket.on('start_game', (code) => {
        const room = partyJo.getRoom(code);
        if (!room || room.hostId !== socket.id) return;
        if (room.gamePhase === 'MATCH_OVER' || room.gamePhase === 'ABANDONED') {
            partyJo.resetMatch(room);
        } else {
            partyJo.startRound(room);
        }
        pjNsp.to(code).emit('state', room);
    });

    socket.on('extend_buffer', ({ code, playerId, additionalSec }) => {
        const room = partyJo.getRoom(code);
        if (!room || room.hostId !== socket.id) return;
        const player = room.players[playerId];
        if (!player || !player.disconnected) return;
        const key = getPjTimerKey(code, player.name);
        if (pjDisconnectTimers[key]) clearTimeout(pjDisconnectTimers[key]);
        const elapsed = Date.now() - (player.disconnectTime || Date.now());
        const originalBuffer = (room.settings.bufferTimeSec || 120) * 1000;
        const remaining = Math.max(0, originalBuffer - elapsed);
        const newTimeout = remaining + (additionalSec || 60) * 1000;
        pjDisconnectTimers[key] = setTimeout(() => {
            const currentRoom = partyJo.getRoom(code);
            if (currentRoom) {
                const p = currentRoom.players[playerId];
                if (p && p.disconnected && !p.kicked_pending) {
                    partyJo.kickPlayer(currentRoom, playerId);
                    pjNsp.to(code).emit('state', currentRoom);
                    pjNsp.to(code).emit('announcement', `⏰ ${p.name} was kicked (timeout)`);
                }
            }
            delete pjDisconnectTimers[key];
        }, newTimeout);
        pjNsp.to(code).emit('announcement', `⏱️ Buffer extended for ${player.name}`);
        pjNsp.to(code).emit('state', room);
    });

    socket.on('kick_player', ({ code, playerId }) => {
        const room = partyJo.getRoom(code);
        if (!room || room.hostId !== socket.id) return;
        const player = room.players[playerId];
        if (!player) return;
        if (room.gamePhase === 'LOBBY') {
            partyJo.removePlayerFromRoom(room, playerId);
            pjNsp.to(code).emit('announcement', `🔴 ${player.name} was kicked from the room`);
        } else {
            if (partyJo.kickPlayer(room, playerId)) {
                const key = getPjTimerKey(code, player.name);
                if (pjDisconnectTimers[key]) { clearTimeout(pjDisconnectTimers[key]); delete pjDisconnectTimers[key]; }
                pjNsp.to(code).emit('announcement', `🔴 ${player.name} kicked by host`);
            }
        }
        pjNsp.to(code).emit('state', room);
    });

    socket.on('next_round', (code) => {
        const room = partyJo.getRoom(code);
        if (!room || room.hostId !== socket.id) return;
        const hostSwitch = partyJo.switchHostIfInactive(room);
        if (hostSwitch) pjNsp.to(code).emit('announcement', `⭐ ${hostSwitch.newHostName} is now the Host!`);
        if (!partyJo.nextRound(code)) return;
        pjNsp.to(code).emit('state', room);
    });

    socket.on('action', ({ code, type, index }) => {
        const room = partyJo.getRoom(code);
        if (!room || room.gamePhase === 'PAUSED') return;
        let changed = false;
        if (room.gamePhase === 'SETUP') {
            changed = partyJo.handleSetupFlip(room, socket.id, index);
        } else if (room.gamePhase === 'PLAYING' || room.gamePhase === 'LAST_TURN') {
            changed = partyJo.handleTurnAction(room, socket.id, type, index);
        }
        if (changed) pjNsp.to(code).emit('state', room);
    });

    socket.on('disconnect', () => {
        if (!currentRoom) return;
        const room = partyJo.getRoom(currentRoom);
        if (room && (['PLAYING', 'SETUP', 'LAST_TURN'].includes(room.gamePhase))) {
            partyJo.markPlayerDisconnected(room, socket.id);
            const hostSwitch = partyJo.switchHostIfInactive(room);
            if (hostSwitch) pjNsp.to(currentRoom).emit('announcement', `⭐ ${hostSwitch.newHostName} is now the Host!`);
            const player = room.players[socket.id];
            if (player) {
                const key = getPjTimerKey(currentRoom, player.name);
                const timeoutMs = (room.settings.bufferTimeSec || 120) * 1000;
                pjDisconnectTimers[key] = setTimeout(() => {
                    const r = partyJo.getRoom(currentRoom);
                    if (r) {
                        const p = r.players[socket.id];
                        if (p && p.disconnected && !p.kicked_pending) {
                            partyJo.kickPlayer(r, socket.id);
                            pjNsp.to(currentRoom).emit('state', r);
                            pjNsp.to(currentRoom).emit('announcement', `⏰ ${p.name} was kicked (timeout)`);
                        }
                    }
                    delete pjDisconnectTimers[key];
                }, timeoutMs);
            }
            pjNsp.to(currentRoom).emit('state', room);
        }
    });
});

// ==================== TAMBOLA NAMESPACE ======================
const tbNsp = io.of('/tambola');
const tbUserRooms = {};

tbNsp.on('connection', (socket) => {
    console.log(`[TAMBOLA] ${socket.id}`);
    let currentRoom = null;

    socket.on('create_room', ({ name }) => {
        if (!name || name.trim().length === 0) return socket.emit('error', 'Name required');
        name = name.trim();
        const code = Math.floor(1000 + Math.random() * 9000).toString();
        const room = tambola.createRoom(code, socket.id, name);
        socket.join(code);
        currentRoom = code;
        tbNsp.to(code).emit('state', room);
        tbNsp.to(code).emit('announcement', `Room ${code} created by ${name}`);
    });

    socket.on('join_room', ({ code, name }) => {
        if (!name || !code) return socket.emit('error', 'Invalid');
        name = name.trim();
        const room = tambola.joinRoom(code, socket.id, name);
        if (!room) return socket.emit('error', 'Cannot join');
        socket.join(code);
        currentRoom = code;
        tbNsp.to(code).emit('state', room);
        tbNsp.to(code).emit('announcement', `${name} joined`);
    });

    socket.on('get_available_rooms', () => socket.emit('available_rooms', tambola.getAvailableRooms()));

    socket.on('start_game', (code) => {
        const room = tambola.getRoom(code);
        if (!room || room.hostId !== socket.id) return;
        tambola.startGame(room);
        tbNsp.to(code).emit('state', room);
        tbNsp.to(code).emit('announcement', 'Game started!');
    });

    socket.on('call_number', (code) => {
        const room = tambola.getRoom(code);
        if (!room || room.hostId !== socket.id) return;
        const num = tambola.callNumber(room);
        if (num !== null) {
            tbNsp.to(code).emit('number_called', num, room.calledNumbers, room.remainingNumbers.length);
            tbNsp.to(code).emit('state', room);
        }
    });

    socket.on('mark_number', ({ code, row, col }) => {
        const room = tambola.getRoom(code);
        if (!room) return;
        const result = tambola.markNumber(room, socket.id, row, col);
        if (result && result.success) {
            tbNsp.to(code).emit('state', room);
            if (result.newPatterns && result.newPatterns.length > 0) {
                result.newPatterns.forEach(pattern => {
                    tbNsp.to(code).emit('pattern_won', pattern, room.winners[pattern]);
                });
            }
        }
    });

    socket.on('reconnect_player', ({ code, name }) => {
        const room = tambola.getRoom(code);
        if (!room) return socket.emit('error', 'Room not found');
        if (tambola.reconnectPlayer(room, socket.id, name)) {
            socket.join(code);
            currentRoom = code;
            tbNsp.to(code).emit('state', room);
            tbNsp.to(code).emit('announcement', `${name} reconnected`);
        } else {
            socket.emit('error', 'Reconnection failed');
        }
    });

    socket.on('disconnect', () => {
        if (!currentRoom) return;
        const room = tambola.getRoom(currentRoom);
        if (room) {
            tambola.markPlayerDisconnected(room, socket.id);
            tbNsp.to(currentRoom).emit('state', room);
        }
    });
});

server.listen(PORT, () => console.log(`✅ Game Hub running on port ${PORT}`));
