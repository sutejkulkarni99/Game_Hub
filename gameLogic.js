const EMOJIS = ['🎲','🃏','🎯','🎪','🥳','🎉','🎊','🎈','🎁','✨','🌟','💥','🔥','🍀','🎮','👾'];
let rooms = {};

function initDeck() {
    let deck = [];
    for (let i = 0; i < 5; i++) deck.push(-2);
    for (let i = 0; i < 10; i++) deck.push(-1);
    for (let i = 0; i < 15; i++) deck.push(0);
    for (let v = 1; v <= 12; v++) {
        for (let i = 0; i < 10; i++) deck.push(v);
    }
    for (let i = deck.length - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1));
        [deck[i], deck[j]] = [deck[j], deck[i]];
    }
    return deck;
}

function reshuffleDiscardIntoDeck(room) {
    if (room.discardPile.length <= 1) return;
    const topDiscard = room.discardPile.pop();
    const remaining = room.discardPile.splice(0);
    for (let i = remaining.length - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1));
        [remaining[i], remaining[j]] = [remaining[j], remaining[i]];
    }
    room.deck = remaining;
    room.discardPile = [topDiscard];
}

function drawCardFromDeck(room) {
    if (room.deck.length === 0) reshuffleDiscardIntoDeck(room);
    if (room.deck.length === 0) return null;
    return room.deck.pop();
}

function checkColumns(p, room) {
    for (let c = 0; c < 4; c++) {
        let i1 = c, i2 = c + 4, i3 = c + 8;
        if (p.grid[i1] !== null && p.grid[i2] !== null && p.grid[i3] !== null &&
            p.visible[i1] && p.visible[i2] && p.visible[i3] &&
            p.grid[i1] === p.grid[i2] && p.grid[i2] === p.grid[i3]) {
            room.discardPile.push(p.grid[i1], p.grid[i2], p.grid[i3]);
            p.grid[i1] = null; p.grid[i2] = null; p.grid[i3] = null;
        }
    }
}

function checkEndGameTrigger(p, room) {
    if (room.gamePhase === 'PLAYING') {
        let allRevealedOrNull = p.grid.every((c, i) => c === null || p.visible[i]);
        if (allRevealedOrNull) { room.gamePhase = 'LAST_TURN'; room.triggerPlayer = p.id; }
    }
}

function calculateScores(room) {
    room.finalScores = {};
    let matchOver = false;
    const target = room.settings.targetScore || 100;

    room.playerOrder.forEach(id => {
        let p = room.players[id];
        if (!p || p.kicked_pending) return;
        let score = 0;
        p.grid.forEach((c, i) => { if (c !== null) { p.visible[i] = true; score += c; } });
        room.finalScores[id] = { name: p.name, rawScore: score, finalScore: score, doubled: false };
    });

    if (room.triggerPlayer && room.finalScores[room.triggerPlayer]) {
        let triggerScore = room.finalScores[room.triggerPlayer].rawScore;
        let validPlayers = room.playerOrder.filter(id => id !== room.triggerPlayer && room.finalScores[id]);
        if (validPlayers.length > 0) {
            let lowestOther = Math.min(...validPlayers.map(id => room.finalScores[id].rawScore));
            if (lowestOther < triggerScore && triggerScore > 0) {
                room.finalScores[room.triggerPlayer].finalScore = triggerScore * 2;
                room.finalScores[room.triggerPlayer].doubled = true;
            }
        }
    }

    room.playerOrder.forEach(id => {
        let p = room.players[id];
        if (!p || p.kicked_pending) return;
        let name = p.name;
        let finalScore = room.finalScores[id]?.finalScore || 0;
        room.globalScores[name] = (room.globalScores[name] || 0) + finalScore;
        if (room.globalScores[name] >= target) matchOver = true;
    });

    const activeCount = room.playerOrder.filter(id => {
        let p = room.players[id];
        return p && !p.kicked_pending;
    }).length;
    if (activeCount <= 1) {
        room.gamePhase = 'ABANDONED';
    } else {
        room.gamePhase = matchOver ? 'MATCH_OVER' : 'ROUND_OVER';
    }
}

function getActivePlayers(room) {
    return room.playerOrder.filter(id => {
        let p = room.players[id];
        return p && !p.kicked_pending && p.status !== 'kicked_pending';
    });
}

function nextTurn(room) {
    room.currentAction = null;
    room.turnIndex = (room.turnIndex + 1) % room.playerOrder.length;
    if (room.gamePhase === 'LAST_TURN') {
        const trigger = room.players[room.triggerPlayer];
        if (!trigger || trigger.kicked_pending) {
            calculateScores(room);
            return;
        }
        if (room.playerOrder[room.turnIndex] === room.triggerPlayer) {
            calculateScores(room);
        }
    }
}

function getAvailableRooms() {
    const available = [];
    for (let code in rooms) {
        let room = rooms[code];
        if (['LOBBY', 'PLAYING', 'SETUP', 'LAST_TURN', 'PAUSED', 'ROUND_OVER'].includes(room.gamePhase)) {
            available.push({
                code: room.code,
                roomName: room.roomName || 'Party Jo',
                playerCount: getActivePlayers(room).length,
                status: room.gamePhase,
                createdAt: room.createdAt
            });
        }
    }
    return available.sort((a, b) => b.createdAt - a.createdAt);
}

module.exports = {
    getRoom: (code) => rooms[code],
    getAvailableRooms,

    createRoom: (code, hostId, hostName, roomName = '', emoji = '🎲') => {
        rooms[code] = {
            code,
            roomName: roomName || 'Party Jo',
            players: {
                [hostId]: {
                    id: hostId, name: hostName, grid: [], visible: Array(12).fill(false),
                    disconnected: false, emoji, status: 'active',
                    kicked_pending: false, wasKicked: false,
                    disconnectTime: null
                }
            },
            playerOrder: [hostId],
            globalScores: { [hostName]: 0 },
            gamePhase: 'LOBBY',
            deck: [], discardPile: [], turnIndex: 0, currentAction: null,
            triggerPlayer: null, setupReveals: {}, finalScores: {},
            hostId: hostId, createdAt: Date.now(),
            settings: { targetScore: 100, bufferTimeSec: 120, rejoinPenalty: 25, roomName: roomName || 'Party Jo' },
            pausedBy: null, previousPhase: null,
            kickedHistory: []
        };
        return rooms[code];
    },

    updateSettings: (code, settings) => {
        let room = rooms[code];
        if (!room) return false;
        if (typeof settings.targetScore === 'number' && settings.targetScore > 0) room.settings.targetScore = settings.targetScore;
        if (typeof settings.bufferTimeSec === 'number' && settings.bufferTimeSec >= 30) room.settings.bufferTimeSec = settings.bufferTimeSec;
        if (typeof settings.rejoinPenalty === 'number' && settings.rejoinPenalty >= 0) room.settings.rejoinPenalty = settings.rejoinPenalty;
        if (typeof settings.roomName === 'string' && settings.roomName.length <= 30) room.roomName = settings.roomName.trim();
        return true;
    },

    joinRoom: (code, id, name, emoji = '🎲') => {
        let room = rooms[code];
        if (!room || room.gamePhase !== 'LOBBY') return null;
        if (Object.values(room.players).some(p => p.name.toLowerCase() === name.toLowerCase())) return null;
        if (getActivePlayers(room).length >= 8) return null;

        room.players[id] = {
            id, name, grid: [], visible: Array(12).fill(false),
            disconnected: false, emoji, status: 'active',
            kicked_pending: false, wasKicked: false,
            disconnectTime: null
        };
        room.playerOrder.push(id);
        if (!(name in room.globalScores)) room.globalScores[name] = 0;
        return room;
    },

    getRoomPlayersByCode: (code) => {
        let room = rooms[code];
        if (!room) return null;
        return {
            code: room.code,
            roomName: room.roomName,
            status: room.gamePhase,
            players: Object.keys(room.players).map(id => {
                let p = room.players[id];
                return {
                    id, name: p.name, emoji: p.emoji, status: p.status,
                    disconnected: p.disconnected,
                    score: room.globalScores[p.name] || 0,
                    kicked_pending: p.kicked_pending
                };
            })
        };
    },

    reconnectPlayer: (code, playerId, name) => {
        let room = rooms[code];
        if (!room) return null;
        for (let oldId in room.players) {
            let p = room.players[oldId];
            if (p.name.toLowerCase() === name.toLowerCase() && p.disconnected && !p.kicked_pending) {
                p.id = playerId;
                p.disconnected = false;
                p.status = 'active';
                p.disconnectTime = null;
                room.players[playerId] = p;
                delete room.players[oldId];
                room.playerOrder = room.playerOrder.map(id => id === oldId ? playerId : id);
                if (room.hostId === oldId) room.hostId = playerId;
                if (room.triggerPlayer === oldId) room.triggerPlayer = playerId;
                if (room.setupReveals && oldId in room.setupReveals) {
                    room.setupReveals[playerId] = room.setupReveals[oldId];
                    delete room.setupReveals[oldId];
                }
                if (room.pausedBy && room.pausedBy.playerId === oldId) {
                    room.gamePhase = room.previousPhase || 'PLAYING';
                    room.pausedBy = null;
                }
                if (p.wasKicked) {
                    const penalty = room.settings.rejoinPenalty || 25;
                    room.globalScores[p.name] = (room.globalScores[p.name] || 0) + penalty;
                    p.wasKicked = false;
                    return { room, penalty, oldId };
                }
                return { room, penalty: 0, oldId };
            }
        }
        return null;
    },

    rejoinAfterKick: (code, playerId, name, emoji) => {
        let room = rooms[code];
        if (!room) return null;
        for (let oldId in room.players) {
            let p = room.players[oldId];
            if (p.name.toLowerCase() === name.toLowerCase() && (p.kicked_pending || p.wasKicked)) {
                const penalty = room.settings.rejoinPenalty || 25;
                room.globalScores[p.name] = (room.globalScores[p.name] || 0) + penalty;
                p.id = playerId;
                p.disconnected = false;
                p.status = 'active';
                p.kicked_pending = false;
                p.wasKicked = false;
                p.disconnectTime = null;
                room.players[playerId] = p;
                delete room.players[oldId];
                room.playerOrder = room.playerOrder.map(id => id === oldId ? playerId : id);
                if (room.hostId === oldId) room.hostId = playerId;
                if (!room.playerOrder.includes(playerId)) room.playerOrder.push(playerId);
                return { room, penalty };
            }
        }
        return null;
    },

    markPlayerDisconnected: (room, playerId) => {
        const p = room.players[playerId];
        if (!p || p.kicked_pending) return room;
        p.disconnected = true;
        p.status = 'offline';
        p.disconnectTime = Date.now();
        if (['PLAYING', 'LAST_TURN', 'SETUP'].includes(room.gamePhase)) {
            room.pausedBy = { playerId, timestamp: Date.now() };
            room.previousPhase = room.gamePhase;
            room.gamePhase = 'PAUSED';
        }
        return room;
    },

    kickPlayer: (room, targetPlayerId) => {
        const p = room.players[targetPlayerId];
        if (!p) return false;
        p.status = 'kicked_pending';
        p.kicked_pending = true;
        p.wasKicked = true;
        room.kickedHistory.push({ name: p.name, timestamp: Date.now() });
        if (room.triggerPlayer === targetPlayerId) room.triggerPlayer = null;
        if (room.pausedBy && room.pausedBy.playerId === targetPlayerId) {
            room.gamePhase = room.previousPhase || 'PLAYING';
            room.pausedBy = null;
        }
        if (getActivePlayers(room).length <= 1 && ['PLAYING','LAST_TURN','SETUP'].includes(room.gamePhase)) {
            room.previousPhase = room.gamePhase;
            room.gamePhase = 'ABANDONED';
        }
        return true;
    },

    removePlayerFromRoom: (room, playerId) => {
        if (!room.players[playerId]) return false;
        delete room.players[playerId];
        room.playerOrder = room.playerOrder.filter(id => id !== playerId);
        if (room.hostId === playerId && room.playerOrder.length > 0) room.hostId = room.playerOrder[0];
        return true;
    },

    switchHostIfInactive: (room) => {
        const currentHost = room.players[room.hostId];
        if (!currentHost || currentHost.disconnected || currentHost.kicked_pending) {
            for (let id of room.playerOrder) {
                if (room.players[id] && !room.players[id].disconnected && !room.players[id].kicked_pending) {
                    room.hostId = id;
                    return { newHostId: id, newHostName: room.players[id].name };
                }
            }
        }
        return null;
    },

    startRound: (room) => {
        const activePlayers = getActivePlayers(room);
        if (activePlayers.length < 2) return false;
        room.deck = initDeck();
        room.discardPile = [drawCardFromDeck(room)];
        activePlayers.forEach(id => {
            let p = room.players[id];
            if (p) {
                p.kicked_pending = false;
                p.wasKicked = false;
                p.grid = [];
                for (let i = 0; i < 12; i++) p.grid.push(drawCardFromDeck(room));
                p.visible = Array(12).fill(false);
                room.setupReveals[id] = 0;
            }
        });
        room.playerOrder = activePlayers;
        room.gamePhase = 'SETUP';
        room.turnIndex = 0;
        room.triggerPlayer = null;
        room.currentAction = null;
        room.pausedBy = null;
        room.previousPhase = null;
        return true;
    },

    handleSetupFlip: (room, playerId, index) => {
        let p = room.players[playerId];
        if (!p || p.disconnected || p.kicked_pending || room.setupReveals[playerId] >= 2 || !p.visible || !p.grid) return false;
        if (room.setupReveals[playerId] < 2 && !p.visible[index] && p.grid[index] !== null) {
            p.visible[index] = true;
            room.setupReveals[playerId]++;
            if (Object.values(room.setupReveals).every(v => v >= 2)) {
                let lowest = 999;
                let firstPlayerId = room.playerOrder[0];
                room.playerOrder.forEach(id => {
                    let player = room.players[id];
                    if (!player || player.disconnected || player.kicked_pending) return;
                    let sum = 0;
                    player.grid.forEach((c, i) => { if (player.visible[i] && c !== null) sum += c; });
                    if (sum < lowest) { lowest = sum; firstPlayerId = id; }
                });
                room.turnIndex = room.playerOrder.indexOf(firstPlayerId);
                room.gamePhase = 'PLAYING';
            }
            return true;
        }
        return false;
    },

    handleTurnAction: (room, playerId, actionType, index = null) => {
        if (!room || room.playerOrder[room.turnIndex] !== playerId || room.gamePhase === 'PAUSED') return false;
        let p = room.players[playerId];
        if (!p || p.disconnected || p.kicked_pending) return false;

        if (actionType === 'draw_deck' && !room.currentAction) {
            const card = drawCardFromDeck(room);
            if (card === null) return false;
            room.currentAction = { type: 'drawn_deck', card };
            return true;
        }
        if (actionType === 'draw_discard' && !room.currentAction && room.discardPile.length > 0) {
            room.currentAction = { type: 'drawn_discard', card: room.discardPile.pop() };
            return true;
        }
        if (actionType === 'discard_drawn' && room.currentAction && room.currentAction.type === 'drawn_deck') {
            room.discardPile.push(room.currentAction.card);
            room.currentAction = { type: 'must_flip' };
            return true;
        }
        if (actionType === 'grid_click' && index !== null && p.grid[index] !== null) {
            if (room.currentAction && (room.currentAction.type === 'drawn_deck' || room.currentAction.type === 'drawn_discard')) {
                let oldCard = p.grid[index];
                p.grid[index] = room.currentAction.card;
                p.visible[index] = true;
                room.discardPile.push(oldCard);
                checkColumns(p, room);
                checkEndGameTrigger(p, room);
                nextTurn(room);
                return true;
            } else if (room.currentAction && room.currentAction.type === 'must_flip') {
                if (!p.visible[index]) {
                    p.visible[index] = true;
                    checkColumns(p, room);
                    checkEndGameTrigger(p, room);
                    nextTurn(room);
                    return true;
                }
            }
        }
        return false;
    },

    nextRound: (code) => {
        let room = rooms[code];
        if (!room) return false;
        return module.exports.startRound(room);
    },

    resetMatch: (room) => {
        if (!room) return;
        room.globalScores = {};
        room.playerOrder.forEach(id => {
            let p = room.players[id];
            if (p && !p.kicked_pending) {
                room.globalScores[p.name] = 0;
                p.wasKicked = false;
            }
        });
        room.kickedHistory = [];
        return module.exports.startRound(room);
    },

    EMOJIS
};
