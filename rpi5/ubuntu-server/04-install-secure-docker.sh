#!/bin/bash
# NodeOne SysAdmin Tool: Docker Bootstrap & Infrastructure Skeleton
# 1. Instaluje Docker Engine (Secure Mode)
# 2. Włącza userns-remap (Audit Requirement)
# 3. Aktywuje grupę docker bez wylogowania (Group Trick)
# 4. Tworzy strukturę katalogów pod usługi NodeOne
set -eou pipefail

# Kolory
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Detekcja użytkownika (tego, który wywołał sudo)
REAL_USER=${SUDO_USER:-$USER}
REAL_GROUP=$(id -gn $REAL_USER)

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}BŁĄD: Uruchom jako root (sudo).${NC}"
  exit 1
fi

echo -e "${BLUE}=== FAZA 1: Instalacja Docker Engine ===${NC}"
# Czyszczenie i repozytoria
apt-get update -qq
apt-get install -y ca-certificates curl gnupg lsb-release -qq
mkdir -p /etc/apt/keyrings
if [ -f "/etc/apt/keyrings/docker.gpg" ]; then rm /etc/apt/keyrings/docker.gpg; fi
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -qq
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -qq

echo -e "${BLUE}=== FAZA 2: Security Hardening (Audit Sec. 3) ===${NC}"
# User Namespace Remapping & Logging
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<EOF
{
  "userns-remap": "default",
  "no-new-privileges": true,
  "icc": false,
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF

# Restart i dodanie użytkownika
systemctl restart docker
usermod -aG docker "$REAL_USER"
echo -e "${GREEN}Docker zainstalowany i zabezpieczony.${NC}"

echo -e "${BLUE}=== FAZA 3: Weryfikacja (Live Activation) ===${NC}"
echo -e "${YELLOW}Testowanie uprawnień bez wylogowania...${NC}"

# Używamy 'sg' aby wykonać komendę z uprawnieniami nowej grupy w bieżącym skrypcie
if sg docker -c "docker info > /dev/null 2>&1"; then
    echo -e "${GREEN}[SUKCES] Grupa docker działa poprawnie!${NC}"
    sg docker -c "docker version --format 'Client: {{.Client.Version}} | Server: {{.Server.Version}}'"
else
    echo -e "${RED}[BŁĄD] Nie udało się uzyskać dostępu do socketa Dockera.${NC}"
fi

echo -e "${BLUE}=== FAZA 4: NodeOne Service Skeleton ===${NC}"
BASE_DIR="/opt/nodeone"
SERVICES=("adguard" "tailscale" "suricata" "watchtower" "vaultwarden" "obsidian" "lsyncd")

echo "Tworzenie struktury w $BASE_DIR..."
mkdir -p "$BASE_DIR"

for SERVICE in "${SERVICES[@]}"; do
    SERVICE_PATH="$BASE_DIR/$SERVICE"
    mkdir -p "$SERVICE_PATH/config"
    mkdir -p "$SERVICE_PATH/data"
    
    # Ustawienie właściciela na realnego użytkownika (abyś mógł edytować configi bez sudo)
    chown -R "$REAL_USER:$REAL_GROUP" "$SERVICE_PATH"
    # Uprawnienia 750 (Właściciel: RWX, Grupa: RX, Inni: Brak) - Zgodne z PoLP
    chmod -R 750 "$SERVICE_PATH"
    echo -e "  [+] Utworzono: $SERVICE"
done

# Tworzenie pliku .env dla zmiennych środowiskowych
ENV_FILE="$BASE_DIR/.env"
if [ ! -f "$ENV_FILE" ]; then
    echo "# NodeOne Environment Variables" > "$ENV_FILE"
    echo "PUID=$(id -u $REAL_USER)" >> "$ENV_FILE"
    echo "PGID=$(id -g $REAL_USER)" >> "$ENV_FILE"
    echo "TZ=Europe/Warsaw" >> "$ENV_FILE"
    chown "$REAL_USER:$REAL_GROUP" "$ENV_FILE"
    chmod 600 "$ENV_FILE" # Tylko właściciel może czytać .env (hasła!)
fi

echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}      NODEONE BOOTSTRAP UKOŃCZONY            ${NC}"
echo -e "${GREEN}=============================================${NC}"
echo "1. Docker jest aktywny i zabezpieczony (userns-remap)."
echo "2. Struktura katalogów czeka w /opt/nodeone."
echo "3. Aby używać dockera w tym terminalu, wpisz teraz:"
echo -e "${YELLOW}   newgrp docker${NC}"
