#!/bin/bash
# ==============================================================================
# NodeOne Master Deployment Script (v4.0 - Final Stable)
# Stos: Tailscale (Mesh) + AdGuard (DNS) + Vaultwarden (Hasła) + Watchtower
# Architektura: Sidecar + UserNS Remap Compatible
# ==============================================================================

set -eou pipefail

# --- KONFIGURACJA SIECI (Zmień jeśli masz inną podsieć!) ---
MY_SUBNET="192.168.1.0/24"
# -----------------------------------------------------------

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'
PROJECT_DIR="/opt/nodeone"

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}BŁĄD: Uruchom jako root (sudo).${NC}"
  exit 1
fi

echo -e "${GREEN}=== 1. PRZYGOTOWANIE SYSTEMU (DNS & PORT 53) ===${NC}"
# Wyłączenie systemd-resolved, aby zwolnić port 53 dla AdGuarda
RESOLVED_CONF="/etc/systemd/resolved.conf"
if ! grep -q "^DNSStubListener=no" "$RESOLVED_CONF"; then
    echo "Wyłączanie Stub Listenera..."
    sed -i 's/#DNSStubListener=yes/DNSStubListener=no/' "$RESOLVED_CONF"
    sed -i 's/DNSStubListener=yes/DNSStubListener=no/' "$RESOLVED_CONF"
    systemctl restart systemd-resolved
fi
# Tymczasowy DNS dla hosta
rm -f /etc/resolv.conf
echo "nameserver 1.1.1.1" > /etc/resolv.conf

echo -e "${GREEN}=== 2. CZYSZCZENIE I KATALOGI ===${NC}"
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

# Zatrzymanie starego stosu
docker compose down --remove-orphans 2>/dev/null || true

# KLUCZOWE: Usuwanie martwych socketów (zapobiega pętli restartów)
echo "Usuwanie starych plików gniazd..."
rm -rf ./tailscale/data/*.sock
rm -rf ./tailscale/data/*.lock

# Tworzenie struktury katalogów
mkdir -p ./tailscale/data ./adguard/data ./adguard/config ./vaultwarden/data

# KLUCZOWE: Naprawa uprawnień dla userns-remap (User Namespaces)
echo "Nadawanie uprawnień do wolumenów..."
chmod -R 777 ./tailscale/data
chmod -R 777 ./adguard/data
chmod -R 777 ./adguard/config
chmod -R 777 ./vaultwarden/data

echo -e "${GREEN}=== 3. GENEROWANIE DOCKER-COMPOSE (SIDECAR) ===${NC}"
cat > docker-compose.yml <<EOF
services:
  # --- GŁÓWNY WĘZEŁ SIECIOWY (Ingress) ---
  tailscale:
    image: tailscale/tailscale:latest
    container_name: nodeone-tailscale
    hostname: nodeone
    environment:
      - TS_EXTRA_ARGS=--advertise-exit-node --advertise-routes=${MY_SUBNET}
      - TS_STATE_DIR=/var/lib/tailscale
      - TS_USERSPACE=true
    volumes:
      - ./tailscale/data:/var/lib/tailscale
    restart: unless-stopped
    ports:
      - "53:53/tcp"   # DNS
      - "53:53/udp"   # DNS
      - "3000:3000/tcp" # AdGuard Panel
      - "8080:80/tcp"   # AdGuard Block Page
      # Port 443 (Vaultwarden) jest obsługiwany wewnątrz przez Tailscale Serve

  # --- ADGUARD HOME (DNS) ---
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

  # --- VAULTWARDEN (Hasła) ---
  vaultwarden:
    image: vaultwarden/server:latest
    container_name: nodeone-vaultwarden
    restart: unless-stopped
    network_mode: "service:tailscale"
    depends_on:
      - tailscale
    volumes:
      - ./vaultwarden/data:/data
    environment:
      - ROCKET_PORT=8081      # Port wewnętrzny
      - SIGNUPS_ALLOWED=true  # ZMIEŃ NA FALSE PO ZAŁOŻENIU KONTA!
      - WEBSOCKET_ENABLED=true

  # --- WATCHTOWER (Aktualizacje) ---
  watchtower:
    image: containrrr/watchtower
    container_name: nodeone-watchtower
    restart: unless-stopped
    userns_mode: "host"       # Wymagane przy userns-remap
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - WATCHTOWER_CLEANUP=true
      - WATCHTOWER_POLL_INTERVAL=86400
      - DOCKER_API_VERSION=1.44 # Fix dla nowoczesnego Dockera
EOF

echo -e "${GREEN}=== 4. URUCHOMIENIE ===${NC}"
docker compose up -d

echo -e "${GREEN}=== 5. INSTRUKCJA KOŃCOWA ===${NC}"
echo "Stos sieciowy został wdrożony."
echo ""
echo -e "${YELLOW}KROK A: Autoryzacja VPN${NC}"
echo "Uruchom poniższą komendę, aby zalogować Tailscale (jeśli trzeba):"
echo -e "${GREEN}docker exec nodeone-tailscale tailscale up --advertise-exit-node --advertise-routes=${MY_SUBNET} --accept-dns=false${NC}"
echo ""
echo -e "${YELLOW}KROK B: Włączenie HTTPS dla Vaultwarden${NC}"
echo "Gdy VPN wstanie, uruchom to, aby wystawić hasła:"
echo -e "${GREEN}docker exec nodeone-tailscale tailscale serve --bg --https=443 http://127.0.0.1:8081${NC}"
echo ""
echo -e "${YELLOW}KROK C: Bezpieczeństwo${NC}"
echo "Pamiętaj, aby po założeniu konta w Vaultwarden zmienić SIGNUPS_ALLOWED=false w docker-compose.yml i zrestartować kontener!"
