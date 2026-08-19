#!/bin/bash
# ============================================================
#  Game Hub: Party Jo + Tambola (Full Script)
#  One command to deploy both games on port 8085.
#  Copy-paste, chmod +x, run.
# ============================================================
PROJECT_DIR="/home/sutej/game_hub"
PORT=8085

echo "=========================================="
echo "  Deploying Game Hub: Party Jo + Tambola"
echo "=========================================="

# Cleanup
docker compose -f "$PROJECT_DIR/docker-compose.yml" down --remove-orphans 2>/dev/null || true
docker ps -a --filter "name=game-hub" --format '{{.ID}}' | xargs -r docker rm -f 2>/dev/null || true
sleep 2

mkdir -p "$PROJECT_DIR/public"
cd "$PROJECT_DIR" || exit 1

# ========================= DOCKERFILE =========================
cat > Dockerfile << 'DOCKER_EOF'
FROM node:18-alpine
WORKDIR /app
COPY package.json ./
RUN npm install --production
COPY . .
EXPOSE 8085
CMD ["node", "server.js"]
DOCKER_EOF

# =================== DOCKER COMPOSE ===========================
cat > docker-compose.yml << 'COMPOSE_EOF'
services:
  game-hub:
    build: .
    ports:
      - "8085:8085"
    environment:
      - NODE_ENV=production
    restart: unless-stopped
    container_name: game-hub
COMPOSE_EOF

# ===================== PACKAGE.JSON ===========================
cat > package.json << 'PKG_EOF'
{
  "name": "game-hub",
  "version": "1.0.0",
  "main": "server.js",
  "dependencies": {
    "express": "^4.18.2",
    "socket.io": "^4.7.2"
  }
}
PKG_EOF

# ==================== HUB PAGE (index.html) ===================
cat > public/index.html << 'HUB_EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Game Hub</title>
    <style>
        :root { --bg: #111; --surface: #222; --accent: #e94560; --gold: #f1c40f; }
        body { font-family: system-ui, sans-serif; background: var(--bg); color: white; text-align: center; margin: 0; padding: 20px; }
        h1 { color: var(--gold); font-size: 3em; margin: 5vh 0 2vh; }
        .game-cards { display: flex; justify-content: center; gap: 40px; flex-wrap: wrap; margin-top: 10vh; }
        .game-card { background: var(--surface); border-radius: 20px; padding: 30px; width: 250px; cursor: pointer; transition: transform 0.3s, box-shadow 0.3s; border: 2px solid transparent; }
        .game-card:hover { transform: translateY(-10px); box-shadow: 0 10px 30px rgba(233,69,96,0.3); border-color: var(--accent); }
        .game-card h2 { margin-top: 0; color: var(--gold); }
        .game-card p { color: #aaa; }
        .emoji { font-size: 4em; margin-bottom: 20px; }
    </style>
</head>
<body>
    <h1>🎮 Game Hub 🎮</h1>
    <p style="color:#aaa;">Choose your game</p>
    <div class="game-cards">
        <div class="game-card" onclick="window.location='/partyjo'">
            <div class="emoji">🃏</div>
            <h2>Party Jo</h2>
            <p>Multiplayer card elimination game inspired by Skyjo</p>
        </div>
        <div class="game-card" onclick="window.location='/tambola'">
            <div class="emoji">🎟️</div>
            <h2>Tambola</h2>
            <p>Classic Indian Housie with tickets & patterns</p>
        </div>
    </div>
</body>
</html>
HUB_EOF

# ==================== PARTY JO GAME LOGIC ======================
cat > gameLogic.js << 'PARTYJO_EOF'
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
PARTYJO_EOF

# ==================== TAMBOLA GAME LOGIC ======================
cat > tambolaLogic.js << 'TAMBOLA_EOF'
let rooms = {};

function generateTicket() {
    const ticket = Array(3).fill().map(() => Array(9).fill(0));
    const colRanges = [
        [1,9], [10,19], [20,29], [30,39], [40,49],
        [50,59], [60,69], [70,79], [80,90]
    ];
    let colCounts = Array(9).fill(0);
    let rowCounts = [0,0,0];
    for (let c = 0; c < 9; c++) { colCounts[c] = 1; }
    let remaining = 6;
    while (remaining > 0) {
        const c = Math.floor(Math.random() * 9);
        if (colCounts[c] < 3) { colCounts[c]++; remaining--; }
    }
    for (let c = 0; c < 9; c++) {
        const count = colCounts[c];
        const availableRows = [0,1,2].filter(r => rowCounts[r] < 5);
        for (let i = 0; i < count; i++) {
            if (i >= availableRows.length) break;
            const r = availableRows[i];
            rowCounts[r]++;
            const range = colRanges[c];
            let num;
            do {
                num = Math.floor(Math.random() * (range[1] - range[0] + 1)) + range[0];
            } while (ticket.some(row => row[c] === num));
            ticket[r][c] = num;
        }
    }
    return ticket;
}

function checkWinners(room, playerId) {
    const p = room.players[playerId];
    if (!p || p.claimedPatterns.includes('full_house')) return [];
    const marks = p.marks;
    const ticket = p.ticket;
    const patterns = [];
    if (!p.claimedPatterns.includes('early_five')) {
        let markCount = 0;
        for (let r = 0; r < 3; r++) for (let c = 0; c < 9; c++) if (ticket[r][c] !== 0 && marks[r][c]) markCount++;
        if (markCount >= 5) patterns.push('early_five');
    }
    const linePatterns = ['top_line', 'middle_line', 'bottom_line'];
    for (let r = 0; r < 3; r++) {
        if (p.claimedPatterns.includes(linePatterns[r])) continue;
        const allMarked = ticket[r].every((num, c) => num === 0 || marks[r][c]);
        if (allMarked) patterns.push(linePatterns[r]);
    }
    if (!p.claimedPatterns.includes('full_house')) {
        let allMarked = true;
        for (let r = 0; r < 3; r++) {
            for (let c = 0; c < 9; c++) {
                if (ticket[r][c] !== 0 && !marks[r][c]) { allMarked = false; break; }
            }
            if (!allMarked) break;
        }
        if (allMarked) patterns.push('full_house');
    }
    return patterns;
}

module.exports = {
    createRoom: (code, hostId, hostName) => {
        rooms[code] = {
            code,
            hostId,
            players: {
                [hostId]: {
                    id: hostId, name: hostName, disconnected: false,
                    status: 'active', ticket: null, marks: null,
                    claimedPatterns: [], disconnectTime: null
                }
            },
            playerOrder: [hostId],
            gamePhase: 'LOBBY',
            calledNumbers: [],
            remainingNumbers: [],
            winners: {},
            createdAt: Date.now()
        };
        return rooms[code];
    },
    getRoom: (code) => rooms[code],
    getAvailableRooms: () => {
        const available = [];
        for (let code in rooms) {
            const room = rooms[code];
            if (['LOBBY', 'PLAYING'].includes(room.gamePhase)) {
                available.push({
                    code,
                    playerCount: Object.values(room.players).filter(p => p.status === 'active' || p.disconnected).length,
                    status: room.gamePhase,
                    createdAt: room.createdAt
                });
            }
        }
        return available.sort((a, b) => b.createdAt - a.createdAt);
    },
    joinRoom: (code, id, name) => {
        const room = rooms[code];
        if (!room || room.gamePhase !== 'LOBBY') return null;
        if (Object.values(room.players).some(p => p.name.toLowerCase() === name.toLowerCase())) return null;
        room.players[id] = {
            id, name, disconnected: false, status: 'active',
            ticket: null, marks: null, claimedPatterns: [], disconnectTime: null
        };
        room.playerOrder.push(id);
        return room;
    },
    startGame: (room) => {
        if (room.playerOrder.length < 1) return false;
        room.playerOrder.forEach(id => {
            const p = room.players[id];
            if (p && p.status === 'active') {
                p.ticket = generateTicket();
                p.marks = Array(3).fill().map(() => Array(9).fill(false));
                p.claimedPatterns = [];
            }
        });
        room.gamePhase = 'PLAYING';
        room.calledNumbers = [];
        room.remainingNumbers = Array.from({length: 90}, (_, i) => i+1);
        room.winners = {};
        return true;
    },
    callNumber: (room) => {
        if (room.remainingNumbers.length === 0) return null;
        const idx = Math.floor(Math.random() * room.remainingNumbers.length);
        const number = room.remainingNumbers.splice(idx, 1)[0];
        room.calledNumbers.push(number);
        return number;
    },
    markNumber: (room, playerId, row, col) => {
        const p = room.players[playerId];
        if (!p || room.gamePhase !== 'PLAYING') return false;
        if (!p.ticket || p.ticket[row][col] === 0) return false;
        if (p.marks[row][col]) return false;
        const number = p.ticket[row][col];
        if (!room.calledNumbers.includes(number)) return false;
        p.marks[row][col] = true;
        const newPatterns = checkWinners(room, playerId);
        if (newPatterns.length > 0) {
            newPatterns.forEach(pattern => {
                if (!room.winners[pattern]) room.winners[pattern] = [];
                room.winners[pattern].push({ name: p.name, id: playerId });
                p.claimedPatterns.push(pattern);
            });
        }
        return { success: true, newPatterns };
    },
    reconnectPlayer: (room, newSocketId, name) => {
        for (const oldId in room.players) {
            const p = room.players[oldId];
            if (p.name.toLowerCase() === name.toLowerCase() && p.disconnected) {
                p.id = newSocketId;
                p.disconnected = false;
                p.status = 'active';
                p.disconnectTime = null;
                room.players[newSocketId] = p;
                delete room.players[oldId];
                room.playerOrder = room.playerOrder.map(id => id === oldId ? newSocketId : id);
                if (room.hostId === oldId) room.hostId = newSocketId;
                return true;
            }
        }
        return false;
    },
    markPlayerDisconnected: (room, playerId) => {
        const p = room.players[playerId];
        if (!p) return;
        p.disconnected = true;
        p.status = 'offline';
        p.disconnectTime = Date.now();
        return room;
    }
};
TAMBOLA_EOF

# ==================== SERVER (Both Games) =====================
cat > server.js << 'SERVER_EOF'
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
SERVER_EOF

# ==================== PARTY JO FRONTEND (partyjo.html) =========
cat > public/partyjo.html << 'PARTYJO_FRONTEND'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <title>Party Jo</title>
    <style>
        :root { --bg: #111; --surface: #222; --accent: #e94560; --gold: #f1c40f; --success: #4caf50; }
        * { touch-action: manipulation; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background: var(--bg); color: white; text-align: center; margin: 0; padding: 10px; overflow-x: hidden; user-select: none; }
        .hidden { display: none !important; }
        input, button, select { padding: 12px; font-size: 16px; border-radius: 8px; margin: 5px; outline: none; font-family: inherit; }
        input { background: var(--surface); color: white; border: 2px solid #444; width: 80%; max-width: 250px; }
        button { background: var(--accent); color: white; border: none; font-weight: bold; cursor: pointer; transition: 0.2s; width: 80%; max-width: 250px; }
        button:disabled { opacity: 0.5; cursor: not-allowed; }
        .area { background: var(--surface); padding: 15px; border-radius: 12px; margin-bottom: 20px; box-shadow: 0 4px 6px rgba(0,0,0,0.3); }
        .flex-center { display: flex; justify-content: center; gap: 20px; align-items: center; flex-wrap: wrap; }
        .grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 6px; width: 100%; margin: 10px auto; }
        #my-grid { max-width: 420px; gap: 8px; }
        .card-container { perspective: 1000px; width: 100%; aspect-ratio: 2/3; cursor: pointer; position: relative; }
        .card-inner { position: absolute; width: 100%; height: 100%; transition: transform 0.4s; transform-style: preserve-3d; }
        .card-container.up .card-inner { transform: rotateY(180deg); }
        .card-face { position: absolute; width: 100%; height: 100%; backface-visibility: hidden; border-radius: 6px; display: flex; align-items: center; justify-content: center; font-family: 'Times New Roman', serif; font-size: 36px; font-weight: bold; border: 2px solid white; }
        .card-back { background: linear-gradient(135deg, #FF007F, #FFFF00, #00FFFF); background-size: 200% 200%; animation: gradientShift 3s ease infinite; color: white; font-size: 12px; font-family: sans-serif; overflow: hidden; }
        .card-back::after { content: "PARTY JO"; position: absolute; transform: rotate(-45deg); font-weight: 900; font-size: 1em; white-space: nowrap; }
        .opp-grid .card-face { font-size: 14px; border-width: 1px; }
        .opp-grid .card-back { font-size: 8px; }
        .opp-grid .card-back::after { font-size: 6px; }
        .card-front { transform: rotateY(180deg); background: white; color: black; background-image: radial-gradient(rgba(0,0,0,0.1) 1px, transparent 1px); background-size: 8px 8px; }
        .val-neg2 { background-color: #1a237e; color: white; }
        .val-neg1 { background-color: #3f51b5; color: white; }
        .val-0 { background-color: #03a9f4; color: white; }
        .val-low { background-color: #4caf50; color: white; }
        .val-mid { background-color: #ffeb3b; color: black; }
        .val-high { background-color: #e91e63; color: white; }
        .modal { position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.95); z-index: 200; display: flex; align-items: center; justify-content: center; flex-direction: column; }
        .modal-content { background: var(--surface); padding: 25px; border-radius: 12px; text-align: left; width: 90%; max-width: 500px; max-height: 80vh; overflow-y: auto; }
        .modal-content h2 { color: var(--gold); margin-top: 0; margin-bottom: 20px; }
        .modal-content label { display: block; margin-bottom: 8px; color: #aaa; font-weight: bold; }
        .modal-content input { width: 100%; max-width: 100%; box-sizing: border-box; margin-bottom: 20px; }
        .announcement { position: fixed; top: 10px; left: 50%; transform: translateX(-50%); background: var(--gold); color: black; padding: 15px 20px; border-radius: 8px; z-index: 1000; animation: slideDown 0.3s ease; }
        @keyframes slideDown { from { transform: translateX(-50%) translateY(-30px); opacity: 0; } to { transform: translateX(-50%) translateY(0); opacity: 1; } }
        @keyframes gradientShift { 0%, 100% { background-position: 0% 50%; } 50% { background-position: 100% 50%; } }
        .pause-banner { background: #c0392b; color: white; padding: 12px; border-radius: 8px; margin: 10px 0; border-left: 4px solid var(--accent); display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 10px; }
        .pause-banner button { background: var(--success); color: white; width: auto; padding: 6px 12px; margin: 0; font-size: 12px; }
        .room-item { background: #333; padding: 12px; margin: 8px 0; border-radius: 8px; cursor: pointer; border-left: 4px solid var(--gold); text-align: left; }
        .player-item { background: #333; padding: 12px; margin: 8px 0; border-radius: 8px; cursor: pointer; border-left: 4px solid var(--gold); display: flex; justify-content: space-between; align-items: center; }
        .status-badge { font-size: 11px; font-weight: bold; padding: 4px 8px; border-radius: 4px; }
        .status-active { background: var(--success); color: white; }
        .status-inactive { background: var(--accent); color: white; }
        .status-kicked { background: #c0392b; color: white; }
        #room { position: relative; margin: 5vh auto; width: 90%; max-width: 400px; }
        .opp-area { width: 48%; min-width: 140px; max-width: 240px; padding: 10px; }
        .opp-grid { max-width: 220px; gap: 4px; }
        .back-btn { position: fixed; top: 10px; left: 10px; background: var(--surface); color: white; border: 2px solid var(--gold); border-radius: 8px; padding: 8px 12px; text-decoration: none; font-weight: bold; z-index: 100; }
    </style>
</head>
<body>
<a href="/" class="back-btn">← Hub</a>

<div id="lobby">
    <h1 style="color: var(--gold); font-size: 44px; margin-top: 5vh;">🎮 PARTY JO 🎮</h1>
    <p style="color: #aaa; margin: 10px 0;">Choose your emoji</p>
    <div class="emoji-picker" id="emoji-picker" style="display: flex; gap: 8px; flex-wrap: wrap; justify-content: center; margin: 15px 0;"></div>
    <input type="text" id="name" placeholder="Your Name" autocomplete="off" /><br>
    <button onclick="createRoom()" style="background: var(--success);">Create New Room</button>
    <hr style="border-color:#333; width:200px; margin:20px auto;">
    <input type="text" id="join-code" placeholder="4-Digit Code" autocomplete="off" /><br>
    <button onclick="joinRoom()" style="background: #03a9f4;">Join Room</button>
    <hr style="border-color:#333; width:200px; margin:20px auto;">
    <button onclick="showAvailableRooms()" style="background: #f39c12;">Rejoin Active Room</button>
</div>

<div id="room" class="hidden">
    <h2 id="room-name"></h2>
    <p style="color:#aaa; font-size:12px;">Share this code!</p>
    <div id="player-list" style="margin: 20px 0;"></div>
    <button onclick="openSettings()" style="background: #888; width: auto; padding: 8px 16px; margin-bottom: 10px;">⚙️ Settings</button>
    <button id="start-btn" onclick="startGame()">Start Game</button>
</div>

<div id="settings-modal" class="modal hidden">
    <div class="modal-content">
        <h2 style="color: var(--gold);">⚙️ Game Settings</h2>
        <div><label>Room Name</label><input type="text" id="setting-room-name" maxlength="30" placeholder="Party Jo" /></div>
        <div><label>Target Score</label><input type="number" id="setting-target-score" min="20" max="500" value="100" /></div>
        <div><label>Disconnect Buffer (seconds)</label><input type="number" id="setting-buffer-time" min="30" max="600" value="120" /></div>
        <div><label>Rejoin Penalty (points)</label><input type="number" id="setting-penalty" min="0" max="100" value="25" /></div>
        <div style="display: flex; gap: 10px; margin-top: 25px;">
            <button onclick="closeSettings()" style="flex:1; background:#444; width:auto;">Cancel</button>
            <button onclick="saveSettings()" style="flex:1; background:var(--accent); width:auto;">Save Changes</button>
        </div>
    </div>
</div>

<div id="available-rooms-modal" class="modal hidden">
    <div class="modal-content">
        <h2 style="color: var(--gold);">Active Rooms</h2>
        <p style="color:#aaa; font-size:13px;">Click a room to see players</p>
        <div id="rooms-list"></div>
        <button onclick="closeModal('available-rooms-modal')" style="width:100%; margin-top:15px; background:#444;">Close</button>
    </div>
</div>

<div id="select-player-modal" class="modal hidden">
    <div class="modal-content">
        <h2 id="room-select-title" style="color: var(--gold);"></h2>
        <p style="color:#aaa; font-size:13px;">Click your inactive name to rejoin</p>
        <div id="players-list"></div>
        <button onclick="closeModal('select-player-modal'); showAvailableRooms();" style="width:100%; margin-top:15px; background:#444;">Back</button>
    </div>
</div>

<div id="game" class="hidden">
    <div id="announcements"></div>
    <div id="pause-alert"></div>
    <div style="display:flex; justify-content:space-between; align-items:center; margin:5px 0;">
        <h3 id="turn-indicator" style="margin:0; flex:1; font-size: 18px;"></h3>
        <span id="room-code-display" style="font-family:monospace; color:var(--gold); font-size: 12px;"></span>
    </div>
    <div class="flex-center" style="align-items:flex-start; flex-wrap:wrap; margin-bottom:15px;">
        <div class="area" style="flex:1; min-width:150px; padding:10px;">
            <h4 style="margin:0 0 10px;">📊 Standings</h4>
            <table id="scoreboard-table" style="width:100%; border-collapse:collapse; font-size:14px;"><thead><tr><th style="color:var(--gold);">Player</th><th style="color:var(--gold);">Score</th></tr></thead><tbody id="scoreboard-body"></tbody></table>
        </div>
        <div class="area flex-center" style="flex:2; min-width:220px; padding:15px;">
            <div>
                <div style="font-size:10px; color:#aaa; margin-bottom:5px;">DECK</div>
                <div class="card-container" style="width:70px;" onclick="action('draw_deck')"><div class="card-inner"><div class="card-face card-back"></div></div></div>
                <div id="deck-count" style="font-size:11px; color:#aaa; margin-top:5px;"></div>
            </div>
            <div><div style="font-size:10px; color:#aaa; margin-bottom:5px;">DISCARD</div><div class="card-container up" style="width:70px;" onclick="action('draw_discard')" id="discard-wrapper"></div></div>
        </div>
    </div>
    <div id="action-area" class="area hidden" style="border:2px solid var(--accent); padding:15px; margin-bottom:15px;">
        <div style="display:flex; justify-content:center; align-items:center; flex-wrap:wrap;">
            <h4 style="margin:0; margin-right:10px;">You Drew:</h4>
            <span id="drawn-card-val" style="display:inline-flex; padding:8px 16px; border-radius:6px; border:2px solid white; font-size:28px; font-weight:bold;"></span>
        </div>
        <button id="discard-btn" onclick="action('discard_drawn')" style="margin-top:15px; width:auto; padding:10px 20px;">Discard & Flip</button>
    </div>
    <div id="my-area" class="area" style="padding:15px;">
        <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:10px;">
            <h3 style="margin:0; font-size:18px;">📋 My Board</h3>
            <div id="my-stats" style="font-size:14px; color:#aaa;"></div>
        </div>
        <div id="my-grid" class="grid"></div>
    </div>
    <div id="others-area" style="display:flex; flex-wrap:wrap; justify-content:center; gap:10px;"></div>
</div>

<div id="game-over" class="hidden">
    <h1 id="go-title" style="font-size:36px; margin-bottom:10px;"></h1>
    <div id="kicked-history"></div>
    <div id="scores-container" style="max-height:50vh; overflow-y:auto; margin-bottom:20px;"></div>
    <div id="go-actions" style="margin-top:20px;"></div>
</div>

<script src="/socket.io/socket.io.js"></script>
<script>
    const socket = io('/partyjo');
    let currentCode = null;
    const EMOJI_LIST = ['🎲', '🃏', '🎯', '🎪', '🥳', '🎉', '🎊', '🎈', '🎁', '✨', '🌟', '💥', '🔥', '🍀', '🎮', '👾'];
    let selectedEmoji = EMOJI_LIST[Math.floor(Math.random() * EMOJI_LIST.length)];

    function buildEmojiPicker() {
        const c = document.getElementById('emoji-picker');
        c.innerHTML = '';
        EMOJI_LIST.forEach(e => {
            const s = document.createElement('span');
            s.textContent = e;
            s.style.fontSize = '24px'; s.style.cursor = 'pointer'; s.style.padding = '5px';
            s.style.borderRadius = '8px';
            s.style.border = e === selectedEmoji ? '2px solid var(--gold)' : '2px solid transparent';
            s.style.backgroundColor = e === selectedEmoji ? '#333' : 'transparent';
            s.onclick = () => { selectedEmoji = e; buildEmojiPicker(); };
            c.appendChild(s);
        });
    }
    buildEmojiPicker();

    function createRoom() {
        const name = document.getElementById('name').value.trim();
        if (!name) return showError('Enter your name');
        socket.emit('create_room', { name, emoji: selectedEmoji });
    }
    function joinRoom() {
        const name = document.getElementById('name').value.trim();
        const code = document.getElementById('join-code').value.trim();
        if (!name) { showError('Enter your name'); return; }
        if (!code || code.length !== 4 || isNaN(code)) { showError('Enter a valid 4-digit code'); return; }
        socket.emit('join_room', { code, name, emoji: selectedEmoji });
    }
    function showAvailableRooms() { socket.emit('get_available_rooms'); }
    function selectRoom(code) { socket.emit('get_room_players', code); }
    function selectPlayer(playerId, name, code) { socket.emit('join_room', { code, name }); }
    function openSettings() { document.getElementById('settings-modal').classList.remove('hidden'); }
    function closeSettings() { document.getElementById('settings-modal').classList.add('hidden'); }
    function closeModal(id) { document.getElementById(id).classList.add('hidden'); }
    function startGame() { socket.emit('start_game', currentCode); }
    function action(t, i=null) { socket.emit('action', { code: currentCode, type: t, index: i }); }

    function saveSettings() {
        socket.emit('update_settings', {
            code: currentCode,
            settings: {
                roomName: document.getElementById('setting-room-name').value || 'Party Jo',
                targetScore: parseInt(document.getElementById('setting-target-score').value) || 100,
                bufferTimeSec: parseInt(document.getElementById('setting-buffer-time').value) || 120,
                rejoinPenalty: parseInt(document.getElementById('setting-penalty').value) || 25
            }
        });
        closeSettings();
    }

    function showError(m) {
        const e = document.createElement('div');
        e.style.cssText = 'position:fixed; top:10px; right:10px; background:var(--accent); color:white; padding:15px; border-radius:8px; z-index:1001;';
        e.innerText = m; document.body.appendChild(e); setTimeout(() => e.remove(), 3000);
    }
    function showAnnouncement(msg) {
        const a = document.getElementById('announcements');
        const el = document.createElement('div'); el.className = 'announcement'; el.innerText = msg;
        a.appendChild(el); setTimeout(() => el.remove(), 4000);
    }
    function getCardClass(v) { if(v===-2) return 'val-neg2'; if(v===-1) return 'val-neg1'; if(v===0) return 'val-0'; if(v>=1&&v<=4) return 'val-low'; if(v>=5&&v<=8) return 'val-mid'; if(v>=9) return 'val-high'; return ''; }
    function createCardHTML(val, isUp, onClick="") {
        if(val===null) return '<div style="border:2px dashed #555; border-radius:6px; width:100%; aspect-ratio:2/3;"></div>';
        const cls = getCardClass(val); const up = isUp?'up':''; const disp = (val===6||val===9)?`<u>${val}</u>`:val;
        return `<div class="card-container ${up}" onclick="${onClick}"><div class="card-inner"><div class="card-face card-back"></div><div class="card-face card-front ${cls}">${disp}</div></div></div>`;
    }
    function getVisibleSum(p) { return p.grid.reduce((s,v,i)=>s+(p.visible[i]&&v!==null?v:0),0); }
    function formatTime(sec) { const m = Math.floor(sec/60); const s = sec%60; return (m>0?m+'m ':'') + s+'s'; }

    socket.on('available_rooms', (rooms) => {
        const list = document.getElementById('rooms-list');
        if (!rooms.length) { list.innerHTML = '<p style="color:#aaa;">No active rooms available</p>'; }
        else { list.innerHTML = rooms.map(r => `<div class="room-item" onclick="selectRoom('${r.code}')"><strong>${r.roomName}</strong><br><span style="color:#aaa; font-size:12px;">Code: ${r.code} | ${r.playerCount} players | ${r.status}</span></div>`).join(''); }
        document.getElementById('available-rooms-modal').classList.remove('hidden');
    });

    socket.on('room_players', (room) => {
        document.getElementById('available-rooms-modal').classList.add('hidden');
        document.getElementById('room-select-title').innerText = room.roomName;
        const list = document.getElementById('players-list');
        list.innerHTML = room.players.map(p => {
            let statusClass = 'status-active', statusTxt = 'ACTIVE', clickable = false;
            if (p.kicked_pending) { statusClass = 'status-kicked'; statusTxt = 'KICKED'; }
            else if (p.disconnected) { statusClass = 'status-inactive'; statusTxt = 'INACTIVE'; clickable = true; }
            return `<div class="player-item" onclick="${clickable ? `selectPlayer('${p.id}', '${p.name}', '${room.code}')` : ''}" style="${clickable?'cursor:pointer;':'opacity:0.6;'}"><div style="text-align:left;"><strong>${p.emoji} ${p.name}</strong><br><span style="color:#aaa; font-size:12px;">Score: ${p.score}</span></div><span class="status-badge ${statusClass}">${statusTxt}</span></div>`;
        }).join('');
        document.getElementById('select-player-modal').classList.remove('hidden');
    });

    socket.on('announcement', (msg) => showAnnouncement(msg));

    socket.on('state', (state) => {
        currentCode = state.code;
        ['lobby', 'room', 'available-rooms-modal', 'select-player-modal', 'game', 'game-over'].forEach(id => document.getElementById(id).classList.add('hidden'));

        if (state.gamePhase === 'LOBBY') {
            document.getElementById('lobby').classList.remove('hidden');
            document.getElementById('room').classList.remove('hidden');
            document.getElementById('room-name').innerText = `${state.roomName} - Code: ${state.code}`;
            const players = Object.values(state.players).filter(p => !p.kicked_pending);
            document.getElementById('player-list').innerHTML = players.map(p => `<div style="background:#333; padding:10px; margin:5px; border-radius:5px;">${p.emoji} ${p.name}${state.hostId === p.id ? ' 👑' : ''}</div>`).join('');
            document.getElementById('start-btn').disabled = players.length < 2;
            document.getElementById('setting-room-name').value = state.roomName;
            document.getElementById('setting-target-score').value = state.settings.targetScore;
            document.getElementById('setting-buffer-time').value = state.settings.bufferTimeSec;
            document.getElementById('setting-penalty').value = state.settings.rejoinPenalty;
        } else if (['ROUND_OVER', 'MATCH_OVER', 'ABANDONED'].includes(state.gamePhase)) {
            document.getElementById('game-over').classList.remove('hidden');
            const goTitle = document.getElementById('go-title');
            if (state.gamePhase === 'ABANDONED') { goTitle.innerText = '❌ GAME ABANDONED'; goTitle.style.color = 'var(--accent)'; }
            else if (state.gamePhase === 'MATCH_OVER') { goTitle.innerText = '🎉 MATCH OVER 🎉'; goTitle.style.color = 'var(--gold)'; }
            else { goTitle.innerText = '🏆 ROUND OVER 🏆'; goTitle.style.color = 'var(--gold)'; }

            if (state.kickedHistory?.length) {
                document.getElementById('kicked-history').innerHTML = `<div class="area" style="background:rgba(192,57,43,0.2); border-left:4px solid #c0392b; text-align:left;"><strong style="color:#c0392b;">⚠️ Kicked Players:</strong><br>` + state.kickedHistory.map(k => `<span style="font-size:12px; color:#aaa;">${k.name}</span>`).join(', ') + '</div>';
            } else { document.getElementById('kicked-history').innerHTML = ''; }

            let scores = document.getElementById('scores-container');
            scores.innerHTML = '';
            if (state.gamePhase !== 'ABANDONED') {
                let sorted = Object.keys(state.globalScores).sort((a,b)=>state.globalScores[b]-state.globalScores[a]);
                sorted.forEach((name, idx) => {
                    let pid = Object.keys(state.players).find(k=>state.players[k]?.name===name);
                    let rs = state.finalScores?.[pid] || { finalScore:0 };
                    scores.innerHTML += `<div class="area" style="${idx===0?'border:2px solid var(--gold)':''}"><div style="display:flex; justify-content:space-between; align-items:center;"><div style="text-align:left;"><strong>#${idx+1} ${state.players[pid]?.emoji||''} ${name}</strong></div><div style="text-align:right;"><span style="font-size:12px; color:#aaa;">Round: ${rs.finalScore}</span><br><strong style="color:var(--gold); font-size:18px;">Total: ${state.globalScores[name]}</strong></div></div></div>`;
                });
            }
            if (state.gamePhase === 'MATCH_OVER') {
                const winner = Object.keys(state.globalScores).sort((a,b)=>state.globalScores[b]-state.globalScores[a])[0];
                document.getElementById('go-actions').innerHTML = `<h2 style="color:var(--gold);">🥇 ${winner} Wins!</h2><button onclick="socket.emit('start_game', currentCode)" style="width:auto; padding:10px 30px;">Play Again</button>`;
            } else if (state.gamePhase === 'ABANDONED') {
                document.getElementById('go-actions').innerHTML = `<p style="color:var(--accent);">Not enough players to continue.</p><button onclick="location.reload()" style="width:auto; padding:10px 30px;">Return to Lobby</button>`;
            } else {
                document.getElementById('go-actions').innerHTML = `<button onclick="socket.emit('next_round', currentCode)" style="width:auto; padding:10px 30px;">Next Round</button>`;
            }
        } else {
            document.getElementById('game').classList.remove('hidden');
            const pauseAlert = document.getElementById('pause-alert');
            if (state.pausedBy) {
                const pausedPlayer = state.players[state.pausedBy.playerId];
                const elapsed = Date.now() - (pausedPlayer.disconnectTime || Date.now());
                const remaining = Math.max(0, (state.settings.bufferTimeSec||120)*1000 - elapsed);
                const remainingSec = Math.ceil(remaining/1000);
                const isHost = state.hostId === socket.id;
                pauseAlert.innerHTML = `<div class="pause-banner"><span>⏸️ GAME PAUSED – waiting for ${pausedPlayer?.emoji||''} ${pausedPlayer?.name||'Player'} (${formatTime(remainingSec)} remaining)</span><div style="display:flex; gap:5px;">${isHost ? `<button onclick="socket.emit('extend_buffer', {code:'${state.code}', playerId:'${state.pausedBy.playerId}', additionalSec:60})">+60s</button>` : ''}${isHost ? `<button onclick="socket.emit('kick_player', {code:'${state.code}', playerId:'${state.pausedBy.playerId}'})">Kick</button>` : ''}</div></div>`;
                pauseAlert.classList.remove('hidden');
            } else { pauseAlert.classList.add('hidden'); }

            document.getElementById('room-code-display').innerText = `${state.roomName} – ${state.code}`;
            const sb = document.getElementById('scoreboard-body');
            sb.innerHTML = '';
            Object.values(state.players).filter(p => !p.kicked_pending).forEach(p => {
                let score = state.globalScores[p.name] || 0;
                let danger = score >= (state.settings.targetScore - 20) ? 'color:var(--accent);' : '';
                sb.innerHTML += `<tr><td>${p.emoji} ${p.name}</td><td style="${danger}">${score}</td></tr>`;
            });

            const turnInd = document.getElementById('turn-indicator');
            const myArea = document.getElementById('my-area');
            const myPlayer = state.players[socket.id];
            if (state.gamePhase === 'SETUP') {
                let count = myPlayer?.visible?.filter(Boolean).length || 0;
                turnInd.innerHTML = `SETUP: FLIP ${2-count} MORE CARD${2-count!==1?'S':''}`;
                turnInd.style.color = 'var(--accent)';
                if(myArea) myArea.classList.add('active-turn');
            } else if (state.gamePhase === 'PAUSED') {
                turnInd.innerHTML = '⏸️ GAME PAUSED'; turnInd.style.color = 'var(--accent)';
            } else {
                let isMyTurn = state.playerOrder[state.turnIndex] === socket.id;
                turnInd.innerHTML = (state.gamePhase==='LAST_TURN'?'⚠️ LAST TURN! ':'') + (isMyTurn?'🎯 YOUR TURN!':`${state.players[state.playerOrder[state.turnIndex]]?.emoji||''} ${state.players[state.playerOrder[state.turnIndex]]?.name||'Unknown'}'s Turn`);
                turnInd.style.color = isMyTurn ? 'var(--gold)' : 'white';
                if(myArea) myArea.classList.toggle('active-turn', isMyTurn);
            }

            const discard = document.getElementById('discard-wrapper');
            let topD = state.discardPile[state.discardPile.length-1];
            discard.innerHTML = topD !== undefined ? createCardHTML(topD, true, "action('draw_discard')") : '<div class="card-inner"><div class="card-face card-front" style="background:#555;"></div></div>';
            document.getElementById('deck-count').innerText = `Cards: ${state.deckCount || 0}`;

            const actionArea = document.getElementById('action-area');
            if (state.playerOrder[state.turnIndex] === socket.id && state.currentAction && state.gamePhase !== 'PAUSED') {
                actionArea.classList.remove('hidden');
                let vs = document.getElementById('drawn-card-val');
                if (state.currentAction.type.includes('drawn')) {
                    let c = state.currentAction.card;
                    vs.innerHTML = (c===6||c===9)?`<u>${c}</u>`:c;
                    vs.className = getCardClass(c);
                    document.getElementById('discard-btn').classList.toggle('hidden', state.currentAction.type !== 'drawn_deck');
                }
            } else { actionArea.classList.add('hidden'); }

            if (myPlayer && !myPlayer.kicked_pending) {
                document.getElementById('my-stats').innerHTML = `Sum: <b>${getVisibleSum(myPlayer)}</b>`;
                document.getElementById('my-grid').innerHTML = myPlayer.grid.map((v,i)=>createCardHTML(v, myPlayer.visible[i], `action('grid_click',${i})`)).join('');
            }
            const others = document.getElementById('others-area');
            others.innerHTML = '';
            state.playerOrder.forEach(id => {
                if (id === socket.id) return;
                let p = state.players[id];
                if (!p || p.kicked_pending) return;
                let isTurn = state.playerOrder[state.turnIndex] === id && state.gamePhase !== 'SETUP' && state.gamePhase !== 'PAUSED';
                others.innerHTML += `<div class="area opp-area" style="${isTurn?'box-shadow:0 0 15px var(--gold); border:2px solid var(--gold)':''}"><h4 style="margin:0; font-size:14px; color:${isTurn?'var(--gold)':'white'}">${p.emoji} ${p.name}</h4><div style="font-size:10px; color:#aaa; margin-bottom:10px;">Sum: ${getVisibleSum(p)}</div><div class="grid opp-grid">${p.grid.map((v,i)=>createCardHTML(v, p.visible[i], '')).join('')}</div></div>`;
            });
        }
    });
    socket.on('error', (msg) => showError(msg));
</script>
</body>
</html>
PARTYJO_FRONTEND

# ==================== TAMBOLA FRONTEND (tambola.html) ==========
cat > public/tambola.html << 'TAMBOLA_FRONTEND'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Tambola</title>
    <style>
        :root { --bg: #111; --surface: #222; --accent: #e94560; --gold: #f1c40f; }
        body { font-family: system-ui, sans-serif; background: var(--bg); color: white; text-align: center; margin: 0; padding: 10px; }
        .back-btn { position: fixed; top: 10px; left: 10px; background: var(--surface); color: white; border: 2px solid var(--gold); border-radius: 8px; padding: 8px 12px; text-decoration: none; font-weight: bold; z-index: 100; }
        input, button { padding: 12px; border-radius: 8px; margin: 5px; font-size: 16px; }
        input { background: var(--surface); color: white; border: 2px solid #444; }
        button { background: var(--accent); color: white; border: none; cursor: pointer; }
        .ticket { display: inline-block; margin: 20px auto; }
        .ticket table { border-collapse: collapse; margin: 0 auto; }
        .ticket td { width: 40px; height: 40px; border: 1px solid #444; text-align: center; vertical-align: middle; font-size: 18px; cursor: pointer; }
        .ticket td.marked { background: var(--accent); color: white; }
        .ticket td.blank { background: transparent; cursor: default; }
        .called-numbers { max-width: 400px; margin: 10px auto; }
        .called-numbers span { display: inline-block; background: var(--surface); padding: 5px 10px; margin: 3px; border-radius: 5px; }
        .winners { margin-top: 20px; }
    </style>
</head>
<body>
<a href="/" class="back-btn">← Hub</a>
<div id="lobby">
    <h1>🎟️ Tambola</h1>
    <input type="text" id="name" placeholder="Your Name" maxlength="20"><br>
    <button onclick="createRoom()">Create Room</button>
    <hr>
    <input type="text" id="join-code" placeholder="4-Digit Code" maxlength="4"><br>
    <button onclick="joinRoom()">Join Room</button>
</div>
<div id="room" class="hidden">
    <h2 id="room-code"></h2>
    <div id="player-list"></div>
    <button id="start-btn" onclick="startGame()">Start Game</button>
</div>
<div id="game" class="hidden">
    <h2 id="game-room-code"></h2>
    <button id="call-btn" onclick="callNumber()">Call Next Number</button>
    <div class="called-numbers" id="called-numbers"></div>
    <div class="ticket" id="ticket"></div>
    <div class="winners" id="winners"></div>
</div>
<script src="/socket.io/socket.io.js"></script>
<script>
    const socket = io('/tambola');
    let currentCode = null;
    let currentTicket = null;
    let currentMarks = null;

    function createRoom() {
        const name = document.getElementById('name').value.trim();
        if (!name) return alert('Enter name');
        socket.emit('create_room', { name });
    }
    function joinRoom() {
        const name = document.getElementById('name').value.trim();
        const code = document.getElementById('join-code').value.trim();
        if (!name || !code) return alert('Enter name and code');
        socket.emit('join_room', { code, name });
    }
    function startGame() { socket.emit('start_game', currentCode); }
    function callNumber() { socket.emit('call_number', currentCode); }

    socket.on('state', (room) => {
        currentCode = room.code;
        if (room.gamePhase === 'LOBBY') {
            document.getElementById('lobby').classList.add('hidden');
            document.getElementById('room').classList.remove('hidden');
            document.getElementById('game').classList.add('hidden');
            document.getElementById('room-code').innerText = `Room: ${room.code}`;
            document.getElementById('player-list').innerHTML = Object.values(room.players).map(p => `<div>${p.name}</div>`).join('');
            document.getElementById('start-btn').disabled = room.hostId !== socket.id;
        } else if (room.gamePhase === 'PLAYING') {
            document.getElementById('lobby').classList.add('hidden');
            document.getElementById('room').classList.add('hidden');
            document.getElementById('game').classList.remove('hidden');
            document.getElementById('game-room-code').innerText = `Room: ${room.code}`;
            const myPlayer = room.players[socket.id];
            if (myPlayer && myPlayer.ticket) {
                currentTicket = myPlayer.ticket;
                currentMarks = myPlayer.marks;
                renderTicket();
            }
            const calledDiv = document.getElementById('called-numbers');
            calledDiv.innerHTML = room.calledNumbers.slice(-10).map(n => `<span>${n}</span>`).join('');
            const winnersDiv = document.getElementById('winners');
            winnersDiv.innerHTML = Object.entries(room.winners).map(([pattern, wins]) => `<div><strong>${pattern}:</strong> ${wins.map(w=>w.name).join(', ')}</div>`).join('');
            document.getElementById('call-btn').disabled = room.hostId !== socket.id;
        }
    });

    function renderTicket() {
        if (!currentTicket) return;
        const ticketDiv = document.getElementById('ticket');
        let html = '<table>';
        for (let r = 0; r < 3; r++) {
            html += '<tr>';
            for (let c = 0; c < 9; c++) {
                const num = currentTicket[r][c];
                if (num === 0) {
                    html += '<td class="blank"></td>';
                } else {
                    const marked = currentMarks[r][c] ? 'marked' : '';
                    html += `<td class="${marked}" onclick="markNumber(${r},${c})">${num}</td>`;
                }
            }
            html += '</tr>';
        }
        html += '</table>';
        ticketDiv.innerHTML = html;
    }

    function markNumber(row, col) {
        socket.emit('mark_number', { code: currentCode, row, col });
    }

    socket.on('number_called', (num, called, remaining) => {
        // Optional: auto-update called list
    });
    socket.on('pattern_won', (pattern, winners) => {
        alert(`${pattern.replace(/_/g, ' ')} won by ${winners.map(w=>w.name).join(', ')}!`);
    });
    socket.on('announcement', msg => alert(msg));
    socket.on('error', msg => alert(msg));
</script>
</body>
</html>
TAMBOLA_FRONTEND

echo "✅ All files created. Building Docker..."
docker compose up -d --build

echo ""
echo "==========================================================="
echo "🎉 Game Hub deployed! Access: http://$(hostname -I | awk '{print $1}'):8085"
echo "Features: Party Jo (fully fixed) + Tambola (full Housie)"
echo "==========================================================="
