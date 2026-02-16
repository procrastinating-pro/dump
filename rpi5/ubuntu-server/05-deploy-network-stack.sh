#!/bin/bash
# ==============================================================================
# NodeOne Network Stack Deployer (Final Stable v3.0)
# ==============================================================================
# Usługi: Tailscale (Exit Node + Subnet), AdGuard Home (DNS), Watchtower
# Architektura: Sidecar (AdGuard współdzieli sieć z Tailscale)
# ==============================================================================

set -eou pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}BŁĄD: Uruchom jako root (sudo).${NC}"
  exit 1
fi

echo -e "${GREEN}=== 1. ZWALNIANIE PORTU 53 (DNS) ===${NC}"
RESOLVED_CONF="/etc/systemd/resolved.conf"
if grep -q "#DNSStubListener=yes" "$RESOLVED_CONF" || grep -q "DNSStubListener=yes" "$RESOLVED_CONF"; then
    echo "Wyłączanie systemd-resolved stub listener..."
    sed -i 's/#DNSStubListener=yes/DNSStubListener=no/' "$RESOLVED_CONF"
    sed -i 's/DNSStubListener=yes/DNSStubListener=no/' "$RESOLVED_CONF"
    systemctl restart systemd-resolved
fi

# Tymczasowa naprawa resolv.conf, aby Docker mógł pobrać obrazy
rm -f /etc/resolv.conf
echo "nameserver 1.1.1.1" > /etc/resolv.conf
echo "Port 53 został zwolniony."

echo -e "${GREEN}=== 2. DETEKCJA SIECI LOKALNEJ ===${NC}"
# Wykrywanie podsieci (omija interfejsy wirtualne dockera)
LOCAL_SUBNET=$(ip route | grep -v "docker" | grep -v "br-" | grep "src" | head -n 1 | awk '{print $1}')

if [[ ! $LOCAL_SUBNET =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
    echo -e "${RED}BŁĄD: Nie wykryto poprawnej podsieci ($LOCAL_SUBNET).${NC}"
    echo -e "${YELLOW}Wpisz podsieć ręcznie (np. 192.168.1.0/24):${NC}"
    read -r LOCAL_SUBNET
fi
echo -e "Używana podsieć: ${YELLOW}$LOCAL_SUBNET${NC}"

echo -e "${GREEN}=== 3. GENEROWANIE KONFIGURACJI SIDECAR ===${NC}"
PROJECT_DIR="/opt/nodeone"
mkdir -p "$PROJECT_DIR/adguard/config" "$PROJECT_DIR/adguard/data" "$PROJECT_DIR/tailscale/data"

cat > "$PROJECT_DIR/docker-compose.yml" <<EOF
services:
  # GŁÓWNY WĘZEŁ SIECIOWY
  tailscale:
    image: tailscale/tailscale:latest
    container_name: nodeone-tailscale
    hostname: nodeone
    environment:
      - TS_EXTRA_ARGS=--advertise-exit-node --advertise-routes=${LOCAL_SUBNET}
      - TS_STATE_DIR=/var/lib/tailscale
      - TS_USERSPACE=true
    volumes:
      - ./tailscale/data:/var/lib/tailscale
    restart: unless-stopped
    ports:
      - "53:53/tcp"
      - "53:53/udp"
      - "3000:3000/tcp"
      - "8080:80/tcp"

  # ADGUARD HOME (SIDECAR)
  adguard:
    image: adguard/adguardhome
    container_name: nodeone-adguard
    restart: unless-stopped
    network_mode: "service:tailscale"
    depends_on:
      - tailscale
    volumes:
      - ./adguard/data:/opt/adguardhome/work
      - ./adguard/config:/opt/adguardhome/conf

  # AUTOMATYCZNE AKTUALIZACJE
  watchtower:
    image: containrrr/watchtower
    container_name: nodeone-watchtower
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - WATCHTOWER_CLEANUP=true
      - WATCHTOWER_POLL_INTERVAL=86400
EOF

echo -e "${GREEN}=== 4. WDRAŻANIE KONTENERÓW ===${NC}"
cd "$PROJECT_DIR"
docker compose down --remove-orphans 2>/dev/null || true
# Usunięcie starego socketu Tailscale jeśli istnieje (zapobiega błędom startu)
rm -f ./tailscale/data/tailscaled.sock
docker compose up -d

echo -e "${GREEN}=== STATUS KOŃCOWY ===${NC}"
echo -e "1. Panel AdGuard: ${YELLOW}http://$(hostname -I | awk '{print $1}'):3000${NC}"
echo -e "2. W panelu Tailscale DNS ustaw IP: ${YELLOW}127.0.0.1${NC}"
echo ""
echo -e "${RED}!!! ABY DOKOŃCZYĆ INSTALACJĘ, URUCHOM PONIŻSZĄ KOMENDĘ !!!${NC}"
echo -e "${GREEN}docker exec nodeone-tailscale tailscale up --advertise-exit-node --advertise-routes=${LOCAL_SUBNET} --accept-dns=false${NC}"
