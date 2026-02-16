#!/bin/bash
# NodeOne SysAdmin Tool: Performance Validation & Cleanup
# Ten skrypt instaluje narzędzia, testuje sprzęt, raportuje wyniki i usuwa narzędzia.
set -eou pipefail

# Kolory dla czytelności
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Sprawdzenie uprawnień root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}BŁĄD: Uruchom ten skrypt jako root (sudo).${NC}"
  exit 1
fi

echo -e "${GREEN}=== FAZA 1: INSTALACJA NARZĘDZI ===${NC}"
echo "Aktualizacja repozytoriów i instalacja fio oraz stress-ng..."
apt-get update -qq
apt-get install -y fio stress-ng -qq > /dev/null
echo "Narzędzia zainstalowane."

# ---------------------------------------------------------
# TEST NVMe
# ---------------------------------------------------------
echo -e "\n${GREEN}=== FAZA 2: TEST WYDAJNOŚCI NVMe (PCIe Gen 3) ===${NC}"
echo -e "${YELLOW}Rozpoczynam test sekwencyjny (Symulacja Backupu)...${NC}"
# Direct=1 omija RAM cache, size=1G wystarczy do testu prędkości
SEQ_RES=$(fio --name=seq_test --ioengine=libaio --rw=write --bs=1M --size=1G --numjobs=1 --direct=1 --group_reporting --minimal)

echo -e "${YELLOW}Rozpoczynam test losowy 4K (Symulacja Bazy Danych PostgreSQL)...${NC}"
# Random RW 75/25, Direct=1
RAND_RES=$(fio --name=rand_test --ioengine=libaio --rw=randrw --rwmixread=75 --bs=4k --size=512M --numjobs=4 --direct=1 --group_reporting --minimal)

# Parsowanie wyników (FIO Minimal Output Format: 3=ReadBW, 4=ReadIOPS, 48=WriteBW, 49=WriteIOPS)
# Dla Seq_Write interesuje nas BW (kb/s) -> przeliczamy na MB/s
SEQ_BW_KB=$(echo "$SEQ_RES" | awk -F';' '{print $48}')
SEQ_BW_MB=$((SEQ_BW_KB / 1024))

# Dla Rand_RW interesuje nas suma IOPS (Read+Write)
RAND_IOPS_R=$(echo "$RAND_RES" | awk -F';' '{print $4}')
RAND_IOPS_W=$(echo "$RAND_RES" | awk -F';' '{print $49}')
TOTAL_IOPS=$((RAND_IOPS_R + RAND_IOPS_W))

# ---------------------------------------------------------
# TEST CPU & THERMAL
# ---------------------------------------------------------
echo -e "\n${GREEN}=== FAZA 3: STRESS TEST CPU & CHŁODZENIA (60s) ===${NC}"
echo "Obciążanie wszystkich 4 rdzeni metodą 'matrixprod'..."
echo "Monitorowanie temperatury w czasie rzeczywistym:"

# Uruchomienie stress-ng w tle
stress-ng --cpu 4 --cpu-method matrixprod --timeout 60s --quiet &
STRESS_PID=$!

MAX_TEMP=0

# Pętla monitorująca temperaturę podczas testu
while kill -0 $STRESS_PID 2>/dev/null; do
    # Odczyt temperatury (w tysięcznych stopnia)
    CURRENT_TEMP_RAW=$(cat /sys/class/thermal/thermal_zone0/temp)
    CURRENT_TEMP=$((CURRENT_TEMP_RAW / 1000))
    
    if [ "$CURRENT_TEMP" -gt "$MAX_TEMP" ]; then
        MAX_TEMP=$CURRENT_TEMP
    fi
    
    # Pasek postępu
    echo -ne "CPU Temp: ${CURRENT_TEMP}°C ... \r"
    sleep 2
done
echo -e "\nTest zakończony."

# ---------------------------------------------------------
# CZYSZCZENIE
# ---------------------------------------------------------
echo -e "\n${GREEN}=== FAZA 4: CZYSZCZENIE (CLEANUP) ===${NC}"
echo "Usuwanie plików tymczasowych fio..."
rm -f seq_test* rand_test*

echo "Odinstalowywanie fio i stress-ng..."
apt-get remove --purge -y fio stress-ng -qq > /dev/null
apt-get autoremove -y -qq > /dev/null
echo "System wyczyszczony."

# ---------------------------------------------------------
# RAPORT KOŃCOWY
# ---------------------------------------------------------
echo -e "\n${GREEN}=============================================${NC}"
echo -e "${GREEN}      RAPORT WYDAJNOŚCI NODEONE (RPi 5)      ${NC}"
echo -e "${GREEN}=============================================${NC}"

echo -e "DYSK NVMe (Gen 3 Check):"
if [ "$SEQ_BW_MB" -ge 700 ]; then
    echo -e "  Przepustowość Liniowa : ${GREEN}${SEQ_BW_MB} MB/s${NC} (Wynik Gen 3 - Znakomity)"
elif [ "$SEQ_BW_MB" -ge 400 ]; then
    echo -e "  Przepustowość Liniowa : ${YELLOW}${SEQ_BW_MB} MB/s${NC} (Wynik Gen 2 - Standard)"
else
    echo -e "  Przepustowość Liniowa : ${RED}${SEQ_BW_MB} MB/s${NC} (Niski wynik - Sprawdź dysk)"
fi

echo -e "BAZA DANYCH (PostgreSQL Readiness):"
if [ "$TOTAL_IOPS" -ge 15000 ]; then
    echo -e "  Losowe IOPS (4K)      : ${GREEN}${TOTAL_IOPS}${NC} (Idealny do baz danych)"
else
    echo -e "  Losowe IOPS (4K)      : ${YELLOW}${TOTAL_IOPS}${NC} (Wystarczający)"
fi

echo -e "CHŁODZENIE (Active Cooler):"
if [ "$MAX_TEMP" -le 65 ]; then
    echo -e "  Maksymalna Temperatura: ${GREEN}${MAX_TEMP}°C${NC} (Bezpiecznie)"
elif [ "$MAX_TEMP" -le 75 ]; then
    echo -e "  Maksymalna Temperatura: ${YELLOW}${MAX_TEMP}°C${NC} (W normie)"
else
    echo -e "  Maksymalna Temperatura: ${RED}${MAX_TEMP}°C${NC} (OSTRZEŻENIE: Throttling możliwy)"
fi
echo -e "${GREEN}=============================================${NC}"
