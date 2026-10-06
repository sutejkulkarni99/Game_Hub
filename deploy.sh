#!/usr/bin/env bash
# ==============================================================================
# Game Hub - Automated Homelab Deployment & Container Backup Script
# Platform: Fedora Linux / Docker / Docker Compose
# Port: 8085 (Configurable via PORT env var)
# ==============================================================================

set -euo pipefail

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Determine script root directory
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

CONTAINER_NAME="game-hub"
IMAGE_NAME="game_hub-game-hub"
PORT="${PORT:-8085}"
BACKUP_DIR="${PROJECT_DIR}/backups"
TIMESTAMP="$(date +'%Y%m%d_%H%M%S')"

echo -e "${CYAN}${BOLD}"
echo "============================================================"
echo "    ⭐ Polaris Game Hub - Homelab Deployment Engine        "
echo "============================================================"
echo -e "${NC}"
echo -e "📂 Project Directory : ${BOLD}${PROJECT_DIR}${NC}"
echo -e "🔌 Target Port       : ${BOLD}${PORT}${NC}"
echo -e "⏰ Timestamp         : ${TIMESTAMP}"
echo "------------------------------------------------------------"

# Step 1: Check Docker & Docker Compose availability
if ! command -v docker &>/dev/null; then
    echo -e "${RED}❌ Docker is not installed or not in PATH.${NC}" >&2
    exit 1
fi

COMPOSE_CMD=""
if docker compose version &>/dev/null; then
    COMPOSE_CMD="docker compose"
elif command -v docker-compose &>/dev/null; then
    COMPOSE_CMD="docker-compose"
else
    echo -e "${RED}❌ Neither 'docker compose' nor 'docker-compose' found.${NC}" >&2
    exit 1
fi

echo -e "${BLUE}ℹ️  Using compose command: ${BOLD}${COMPOSE_CMD}${NC}"

# Step 2: Backup Currently Running Container
echo -e "\n${YELLOW}🔍 Checking for active container to back up...${NC}"
RUNNING_CONTAINER_ID=$(docker ps -q --filter "name=^/${CONTAINER_NAME}$" || true)

if [ -n "$RUNNING_CONTAINER_ID" ]; then
    BACKUP_TAG="game-hub-backup:${TIMESTAMP}"
    LATEST_BACKUP_TAG="game-hub-backup:latest"
    echo -e "📦 Found running container [${CYAN}${RUNNING_CONTAINER_ID:0:12}${NC}]."
    echo -e "💾 Creating snapshot commit: ${BOLD}${BACKUP_TAG}${NC}..."
    
    if docker commit "$RUNNING_CONTAINER_ID" "$BACKUP_TAG" >/dev/null; then
        docker tag "$BACKUP_TAG" "$LATEST_BACKUP_TAG" || true
        echo -e "${GREEN}✅ Running container successfully committed and tagged as:${NC}"
        echo -e "   • ${BACKUP_TAG}"
        echo -e "   • ${LATEST_BACKUP_TAG}"
    else
        echo -e "${YELLOW}⚠️  Container snapshot commit returned non-zero; continuing with image tag backup.${NC}"
    fi

    # Prune older backup images, keeping the 3 most recent
    echo -e "🧹 Pruning old backup images (retaining latest 3 snapshots)..."
    OLD_BACKUPS=$(docker images --format '{{.Repository}}:{{.Tag}} {{.CreatedAt}}' | grep '^game-hub-backup:20' | sort -k2 -r | awk '{print $1}' | tail -n +4 || true)
    if [ -n "$OLD_BACKUPS" ]; then
        for img in $OLD_BACKUPS; do
            echo -e "   Removing old backup: ${img}"
            docker rmi "$img" 2>/dev/null || true
        done
    fi
else
    echo -e "${BLUE}ℹ️  No active container named '${CONTAINER_NAME}' currently running. Skipping snapshot commit.${NC}"
fi

# Step 3: Build the New Docker Image (Zero-Downtime-Prep)
echo -e "\n${BLUE}🔨 Building new Game Hub Docker container image...${NC}"
if ! $COMPOSE_CMD build; then
    echo -e "${RED}❌ Docker build failed! Aborting deployment without stopping existing services.${NC}" >&2
    exit 1
fi
echo -e "${GREEN}✅ Build completed successfully!${NC}"

# Step 4: Stop and Replace with the New Container
echo -e "\n${YELLOW}🔄 Stopping previous deployment & launching new container...${NC}"
$COMPOSE_CMD down --remove-orphans 2>/dev/null || true

# Launch updated container
$COMPOSE_CMD up -d

# Step 5: Verification & Health Check
echo -e "\n${CYAN}⏳ Verifying server health on port ${PORT}...${NC}"
HEALTHY=false
for i in {1..15}; do
    if curl -s -f -o /dev/null "http://127.0.0.1:${PORT}/"; then
        HEALTHY=true
        break
    fi
    sleep 1
    echo -n "."
done
echo ""

if [ "$HEALTHY" = true ]; then
    # Detect primary IP addresses for user convenience
    LAN_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")
    TAILSCALE_IP=$(ip -4 addr show tailscale0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || true)

    echo -e "${GREEN}${BOLD}"
    echo "============================================================"
    echo "    🎉 GAME HUB DEPLOYED & RUNNING SUCCESSFULLY!            "
    echo "============================================================"
    echo -e "${NC}"
    echo -e "🚀 Local URL     : ${BOLD}http://localhost:${PORT}/${NC}"
    echo -e "🏠 LAN URL       : ${BOLD}http://${LAN_IP}:${PORT}/${NC}"
    if [ -n "$TAILSCALE_IP" ]; then
        echo -e "🌐 Tailscale URL : ${BOLD}http://${TAILSCALE_IP}:${PORT}/${NC}"
    fi
    echo -e "🃏 Party Jo      : http://${LAN_IP}:${PORT}/partyjo"
    echo -e "🎟️  Tambola       : http://${LAN_IP}:${PORT}/tambola"
    echo "------------------------------------------------------------"
    echo -e "💡 Backup snapshot saved as: ${BOLD}game-hub-backup:${TIMESTAMP}${NC}"
    echo -e "   Rollback command if needed: ${YELLOW}docker run -d -p ${PORT}:${PORT} ${LATEST_BACKUP_TAG}${NC}"
    echo "============================================================"
else
    echo -e "${RED}❌ Health check failed after 15 seconds!${NC}"
    echo -e "${YELLOW}Dumping recent container logs:${NC}"
    $COMPOSE_CMD logs --tail=40
    echo -e "\n${YELLOW}To rollback to your snapshot backup:${NC}"
    echo -e "  docker run -d --name game-hub-rollback -p ${PORT}:${PORT} game-hub-backup:latest"
    exit 1
fi
