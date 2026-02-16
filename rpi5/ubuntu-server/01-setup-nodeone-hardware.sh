#!/bin/bash
# NodeOne SysAdmin Tool: Hardware Setup v2.0 (Smart Search)
# Ten skrypt sam znajdzie config.txt w /media i zaaplikuje zmiany
set -u

echo "--- NodeOne Hardware Provisioning v2.0 ---"

# 1. INTELIGENTNE WYSZUKIWANIE
# Szukamy pliku config.txt gdziekolwiek w /media, który ma w ścieżce 'system-boot' lub 'boot'
# Ignorujemy błędy uprawnień (2>/dev/null)
echo "INFO: Przeszukiwanie zamontowanych dysków w /media..."
FOUND_FILE=$(find /media -maxdepth 4 -name "config.txt" 2>/dev/null | grep -E "system-boot|bootfs" | head -n 1)

# Jeśli find nic nie znalazł, spróbujmy szerszego wyszukiwania (jakakolwiek partycja boot)
if [ -z "$FOUND_FILE" ]; then
    FOUND_FILE=$(find /media -maxdepth 4 -name "config.txt" 2>/dev/null | grep "firmware" | head -n 1)
fi

# 2. WERYFIKACJA ZNALEZISKA
if [ -z "$FOUND_FILE" ]; then
    echo "BŁĄD KRYTYCZNY: Nie znaleziono pliku config.txt!"
    echo "Upewnij się, że dysk jest zamontowany. Sprawdź komendą: df -h"
    exit 1
fi

echo "SUKCES: Znaleziono plik konfiguracyjny: $FOUND_FILE"
CONFIG_FILE="$FOUND_FILE"

# 3. TREŚĆ KONFIGURACJI
read -r -d '' NODEONE_CONFIG << EOM

# ================================================================
# [NODEONE HARDWARE OPTIMIZATION]
# ================================================================
# --- NVMe Storage Optimization ---
dtparam=pciex1
dtparam=pciex1_gen=3

# --- Aggressive Cooling Profile ---
dtparam=fan_temp0=45000
dtparam=fan_temp0_hyst=2000
dtparam=fan_temp0_speed=64
dtparam=fan_temp1=52000
dtparam=fan_temp1_hyst=2000
dtparam=fan_temp1_speed=128
dtparam=fan_temp2=60000
dtparam=fan_temp2_hyst=2000
dtparam=fan_temp2_speed=192
dtparam=fan_temp3=68000
dtparam=fan_temp3_hyst=2000
dtparam=fan_temp3_speed=255
# ================================================================
EOM

# 4. APLIKACJA ZMIAN
# Kopia zapasowa
cp "$CONFIG_FILE" "${CONFIG_FILE}.bak_v2"
echo "INFO: Kopia zapasowa utworzona."

# Idempotency Check
if grep -q "NODEONE HARDWARE OPTIMIZATION" "$CONFIG_FILE"; then
    echo "UWAGA: Konfiguracja już istnieje w pliku."
else
    echo "$NODEONE_CONFIG" >> "$CONFIG_FILE"
    echo "SUKCES: Zapisano zmiany w $CONFIG_FILE"
fi

# 5. SYNCHRONIZACJA
echo "INFO: Zapisywanie na dysk (sync)..."
sync
echo "GOTOWE."
