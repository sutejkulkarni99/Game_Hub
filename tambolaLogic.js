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
