#!/bin/bash
# NodeOne SysAdmin Tool: Network Validator (Standalone Binary)
# Omija problemy z repozytorium apt, pobierając binarkę bezpośrednio.
set -eou pipefail

# Kolory
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== NODEONE NETWORK AUDIT START ===${NC}"

# 1. Przygotowanie środowiska
echo "INFO: Sprawdzanie zależności..."
if ! command -v wget &> /dev/null; then
    echo "Instalowanie wget..."
    sudo apt-get update && sudo apt-get install -y wget
fi

# 2. Pobieranie oficjalnego klienta (Direct Download)
echo "INFO: Pobieranie Ookla Speedtest (ARM64)..."
wget -q https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-aarch64.tgz -O speedtest.tgz

# 3. Rozpakowanie
echo "INFO: Rozpakowywanie..."
tar -xzf speedtest.tgz speedtest

# 4. Uruchomienie Testu
echo -e "${YELLOW}INFO: Rozpoczynam pomiar... Proszę czekać (ok. 30s).${NC}"

# Uruchamiamy test i zapisujemy wynik JSON do zmiennej
RESULT_JSON=$(./speedtest --accept-license --accept-gdpr -f json)

# 5. Parsowanie Wyników (bez jq, czysty bash/grep)
# Wyciągamy wartości (Bytes) i konwertujemy na Mbps
DL_BYTES=$(echo "$RESULT_JSON" | grep -o '"bandwidth":[0-9]*' | head -1 | cut -d':' -f2)
UL_BYTES=$(echo "$RESULT_JSON" | grep -o '"bandwidth":[0-9]*' | tail -1 | cut -d':' -f2)
PING_MS=$(echo "$RESULT_JSON" | grep -o '"latency":[0-9]*' | head -1 | cut -d':' -f2)
URL_RESULT=$(echo "$RESULT_JSON" | grep -o '"result":{"id":"[^"]*","url":"[^"]*"' | grep -o 'https://[^"]*')

# Matematyka w bashu (awk dla precyzji float)
DL_MBPS=$(awk "BEGIN {printf \"%.2f\", $DL_BYTES * 8 / 1000000}")
UL_MBPS=$(awk "BEGIN {printf \"%.2f\", $UL_BYTES * 8 / 1000000}")

# 6. Raport SysAdmina
echo -e "\n${GREEN}=== WYNIKI TESTU ===${NC}"
echo -e "Ping (Opóźnienie) : ${YELLOW}${PING_MS} ms${NC}"
echo -e "Pobieranie (Down) : ${GREEN}${DL_MBPS} Mbps${NC}"
echo -e "Wysyłanie (Up)    : ${GREEN}${UL_MBPS} Mbps${NC}"
echo -e "Link do wyniku    : $URL_RESULT"

echo -e "\n${GREEN}=== ANALIZA INFRASTRUKTURY ===${NC}"

# Sprawdzenie "wąskiego gardła" kabla Ethernet
if (( $(echo "$DL_MBPS > 90" | bc -l) && $(echo "$DL_MBPS < 100" | bc -l) )); then
    echo -e "${RED}[!] OSTRZEŻENIE KABLOWE:${NC}"
    echo "Twój wynik jest podejrzanie bliski 100 Mbps ($DL_MBPS Mbps)."
    echo "Oznacza to, że Twój kabel Ethernet lub Switch negocjuje prędkość 'Fast Ethernet' (100Mb)."
    echo "Wymień kabel na Cat 5e lub Cat 6, aby uzyskać pełny Gigabit."
elif (( $(echo "$DL_MBPS > 800" | bc -l) )); then
    echo -e "${GREEN}[OK] Pełna prędkość Gigabit Ethernet.${NC}"
    echo "Karty sieciowe i okablowanie działają z maksymalną wydajnością."
else
    echo "Status: Wynik w normie (zależny od ISP)."
fi

# 7. Czyszczenie (Cleanup)
echo -e "\nINFO: Usuwanie plików tymczasowych..."
rm speedtest speedtest.tgz speedtest.md speedtest.5 2>/dev/null

echo "Zakończono."
