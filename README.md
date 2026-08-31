# Game Hub — Party Jo & Tambola

[![Docker](https://img.shields.io/badge/Docker-✓-blue.svg)](https://www.docker.com/)
[![Node.js](https://img.shields.io/badge/Node.js-18+-green.svg)](https://nodejs.org/)
[![Socket.io](https://img.shields.io/badge/Socket.io-4.7+-yellow.svg)](https://socket.io/)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**Game Hub** is a Dockerised multiplayer gaming platform featuring two full‑fledged games: **Party Jo** (card elimination) and **Tambola** (Indian Housie). Built with Node.js, Express, Socket.io, and served via a single container.

---

## 🎮 Games Included

### 1. Party Jo
- Inspired by Skyjo — a card‑elimination game for 2–8 players.
- **Features**:
  - Grid‑based card layout (4×3) with hidden cards.
  - Draw from deck or discard pile.
  - Flip cards, eliminate matching columns, trigger last‑turn penalty.
  - Host controls: start game, kick players, extend disconnect buffer.
  - Auto‑reconnect with rejoin penalty.
  - Full game flow: Setup → Playing → Last Turn → Round Over → Match Over.

### 2. Tambola
- Classic Indian Housie (Bingo) with 90 numbers and 3×9 tickets.
- **Features**:
  - Auto‑generated tickets for each player.
  - Manual or auto‑call with adjustable speed.
  - Pattern detection: Early Five, Top/Middle/Bottom Line, Full House.
  - Audio announcements for each called number.
  - Host controls: call numbers, view winners in real time.

---

## 🚀 Quick Start

### Prerequisites
- **Docker** and **Docker Compose** (recommended)
- Or **Node.js 18+** and **npm** (for local development)

### Deploy with Docker (Recommended)

```bash
# Clone the repository
git clone https://github.com/sutejkulkarni99/Game_Hub.git
cd Game_Hub

# Run the deployment script (builds and starts the container)
chmod +x deploy.sh
./deploy.sh

Access the hub at: http://localhost:8085
Manual Local Deployment (Without Docker)
bash

npm install
node server.js

📁 Repository Structure
text

Game_Hub/
├── Dockerfile                # Multi‑stage container build
├── docker-compose.yml        # One‑command deployment
├── deploy.sh                 # Automation script (build + run)
├── package.json              # Node.js dependencies
├── server.js                 # Express + Socket.io server (both games)
├── gameLogic.js              # Party Jo game engine
├── tambolaLogic.js           # Tambola game engine
├── public/
│   ├── index.html            # Hub landing page
│   ├── partyjo.html          # Party Jo frontend
│   └── tambola.html          # Tambola frontend
└── backup_atheris/           # Legacy backup (ignore)

🛠️ Tech Stack
LayerTechnologies
RuntimeNode.js, Express
RealtimeSocket.io (WebSockets)
FrontendVanilla HTML, CSS (responsive), JavaScript
ContainerDocker, Docker Compose
Developmentnodemon (optional), npm
🔧 Configuration
Environment Variables (optional)
VariableDefaultDescription
PORT8085Port the server listens on

You can override them in docker-compose.yml or when running locally.
Game Settings (in‑game)

    Party Jo: Target score, disconnect buffer, rejoin penalty, room name.

    Tambola: Auto‑call speed, audio toggle.

📸 Screenshots

(Add screenshots of the hub, Party Jo board, and Tambola ticket here)
🤝 Contributing

Contributions are welcome! Please open an issue or submit a pull request.
📜 License

MIT License — see LICENSE for details.
👤 Author

Sutej Kulkarni

    Email: sutejkulkarni99@gmail.com

    LinkedIn: linkedin.com/in/sutej-kulkarni

    GitHub: github.com/sutejkulkarni99

🙏 Acknowledgments

    Built as a fun homelab project to host multiplayer games for friends and family.

    Inspired by classic card games and Indian Housie traditions.

📌 Keywords

multiplayer games, Node.js, Socket.io, Docker, Party Jo, Tambola, Housie, card game, real-time gaming, homelab
