let rooms = {};

/**
 * Mathematically guaranteed Indian Housie (Tambola) 3x9 Ticket Generator
 * - Exactly 15 numbers total
 * - Exactly 5 numbers and 4 blanks in each of the 3 rows
 * - Each column has 1, 2, or 3 numbers
 * - Numbers in each column are sorted in strictly ascending order from top to bottom
 */
function generateTicket() {
    const colRanges = [
        [1, 9], [10, 19], [20, 29], [30, 39], [40, 49],
        [50, 59], [60, 69], [70, 79], [80, 90]
    ];

    let grid;
    let attempts = 0;
    while (attempts < 1000) {
        attempts++;
        grid = Array(3).fill().map(() => Array(9).fill(0));
        const rowSums = [0, 0, 0];

        // Step 1: Assign at least 1 number to each column (9 numbers)
        const cols = [0, 1, 2, 3, 4, 5, 6, 7, 8].sort(() => Math.random() - 0.5);
        for (const c of cols) {
            const availRows = [0, 1, 2].filter(r => rowSums[r] < 5);
            if (availRows.length === 0) break;
            const r = availRows[Math.floor(Math.random() * availRows.length)];
            grid[r][c] = 1;
            rowSums[r]++;
        }

        // Step 2: Distribute remaining 6 numbers so each row has exactly 5
        let valid = true;
        for (let r = 0; r < 3; r++) {
            while (rowSums[r] < 5) {
                const availCols = [0, 1, 2, 3, 4, 5, 6, 7, 8].filter(c => {
                    const colCount = grid[0][c] + grid[1][c] + grid[2][c];
                    return grid[r][c] === 0 && colCount < 3;
                });
                if (availCols.length === 0) {
                    valid = false;
                    break;
                }
                const c = availCols[Math.floor(Math.random() * availCols.length)];
                grid[r][c] = 1;
                rowSums[r]++;
            }
            if (!valid) break;
        }

        if (valid && rowSums.every(s => s === 5)) {
            const colSums = [0, 1, 2, 3, 4, 5, 6, 7, 8].map(c => grid[0][c] + grid[1][c] + grid[2][c]);
            if (colSums.every(s => s >= 1 && s <= 3)) {
                break; // Guaranteed valid structure
            }
        }
    }

    // Step 3: Populate numbers from column ranges and SORT vertically
    const ticket = Array(3).fill().map(() => Array(9).fill(0));
    for (let c = 0; c < 9; c++) {
        const rowsWithNum = [0, 1, 2].filter(r => grid[r][c] === 1);
        const count = rowsWithNum.length;
        const [minVal, maxVal] = colRanges[c];

        const picked = new Set();
        while (picked.size < count) {
            const num = Math.floor(Math.random() * (maxVal - minVal + 1)) + minVal;
            picked.add(num);
        }

        const sortedNums = Array.from(picked).sort((a, b) => a - b);
        for (let i = 0; i < count; i++) {
            ticket[rowsWithNum[i]][c] = sortedNums[i];
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

    // Early Five
    if (!p.claimedPatterns.includes('early_five')) {
        let markCount = 0;
        for (let r = 0; r < 3; r++) for (let c = 0; c < 9; c++) if (ticket[r][c] !== 0 && marks[r][c]) markCount++;
        if (markCount >= 5) patterns.push('early_five');
    }

    // Four Corners (First & last numbers of top and bottom lines)
    if (!p.claimedPatterns.includes('four_corners')) {
        const getRowCorners = (r) => {
            const cols = [];
            for (let c = 0; c < 9; c++) if (ticket[r][c] !== 0) cols.push(c);
            return cols.length >= 2 ? [cols[0], cols[cols.length - 1]] : cols;
        };
        const topCorners = getRowCorners(0);
        const bottomCorners = getRowCorners(2);
        if (topCorners.length === 2 && bottomCorners.length === 2) {
            const allCorners = marks[0][topCorners[0]] && marks[0][topCorners[1]] &&
                               marks[2][bottomCorners[0]] && marks[2][bottomCorners[1]];
            if (allCorners) patterns.push('four_corners');
        }
    }

    // Lines
    const linePatterns = ['top_line', 'middle_line', 'bottom_line'];
    for (let r = 0; r < 3; r++) {
        if (p.claimedPatterns.includes(linePatterns[r])) continue;
        const allMarked = ticket[r].every((num, c) => num === 0 || marks[r][c]);
        if (allMarked) patterns.push(linePatterns[r]);
    }

    // Full House
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
            autoCall: false,
            callIntervalSec: 5,
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

        // Reclaim existing player slot if rejoining/refreshing in lobby
        const existingId = Object.keys(room.players).find(pid => room.players[pid].name.toLowerCase() === name.toLowerCase());
        if (existingId) {
            const p = room.players[existingId];
            delete room.players[existingId];
            p.id = id;
            p.disconnected = false;
            p.status = 'active';
            room.players[id] = p;
            room.playerOrder = room.playerOrder.map(pid => pid === existingId ? id : pid);
            if (room.hostId === existingId) room.hostId = id;
            return room;
        }

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
        room.remainingNumbers = Array.from({ length: 90 }, (_, i) => i + 1);
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
    },

    switchHostIfInactive: (room) => {
        const currentHost = room.players[room.hostId];
        if (!currentHost || currentHost.disconnected) {
            for (let id of room.playerOrder) {
                if (room.players[id] && !room.players[id].disconnected) {
                    room.hostId = id;
                    return { newHostId: id, newHostName: room.players[id].name };
                }
            }
        }
        return null;
    },

    getRoomPlayersByCode: (code) => {
        const room = rooms[code];
        if (!room) return null;
        return {
            code: room.code,
            roomName: `Tambola Room ${room.code}`,
            status: room.gamePhase,
            players: Object.keys(room.players).map(id => {
                const p = room.players[id];
                return {
                    id,
                    name: p.name,
                    status: p.status,
                    disconnected: p.disconnected,
                    score: p.claimedPatterns ? p.claimedPatterns.length : 0,
                    kicked_pending: false
                };
            })
        };
    },

    checkWinners,

    claimPattern: (room, playerId, pattern) => {
        const p = room.players[playerId];
        if (!p || room.gamePhase !== 'PLAYING') return { success: false, reason: 'Game not in progress' };
        if (p.claimedPatterns && p.claimedPatterns.includes(pattern)) return { success: false, reason: 'Already claimed by you' };

        const eligible = checkWinners(room, playerId);
        if (eligible.includes(pattern)) {
            if (!room.winners[pattern]) room.winners[pattern] = [];
            room.winners[pattern].push({ name: p.name, id: playerId });
            p.claimedPatterns.push(pattern);
            return { success: true, pattern, playerName: p.name };
        }
        return { success: false, reason: 'Bogey / False Claim: Incomplete numbers on your ticket!' };
    },

    restartGame: (room) => {
        return module.exports.startGame(room);
    }
};
