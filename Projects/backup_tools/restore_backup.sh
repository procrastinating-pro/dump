#!/usr/bin/env bash
set -euo pipefail

# --- 0. SPRAWDZENIE UPRAWNIEŃ SUDO ---
if [[ $EUID -ne 0 ]]; then
   echo -e "\033[0;31mBŁĄD: Musisz uruchomić skrypt z sudo!\033[0m"
   echo -e "Użyj: \033[0;32msudo $0\033[0m"
   exit 1
fi

# --- 1. WYKRYWANIE UŻYTKOWNIKA ---
REAL_USER=${SUDO_USER:-$USER}
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
USB_MOUNT="/media/$REAL_USER/backup"
LOCAL_BACKUP_DIR="$REAL_HOME/Backups"

BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# --- 2. WYBÓR ŹRÓDŁA ---
echo -e "${BLUE}Zalogowany jako: $REAL_USER${NC}"
echo -e "${BLUE}Gdzie szukać plików backupu?${NC}"
options=("Folder lokalny (~/Backups)" "Pendrive" "Wyjście")
select opt in "${options[@]}"; do
    case $opt in
        "Folder lokalny (~/Backups)")
            SOURCE_DIR="$LOCAL_BACKUP_DIR"
            break ;;
        "Pendrive")
            # Wykrywanie pendrive'a po etykiecie 'backup'
            DEV_NAME=$(lsblk -dno NAME,LABEL | grep "backup" | awk '{print $1}' | head -n 1 || echo "")
            if [[ -z "$DEV_NAME" ]]; then
                echo -e "${RED}Błąd: Nie znaleziono pendrive'a o etykiecie 'backup'!${NC}"
                exit 1
            fi
            DEV_NODE="/dev/$DEV_NAME"
            mkdir -p "$USB_MOUNT"
            umount "$DEV_NODE" 2>/dev/null || true
            mount "$DEV_NODE" "$USB_MOUNT"
            chown "$REAL_USER:$REAL_USER" "$USB_MOUNT"
            SOURCE_DIR="$USB_MOUNT"
            break ;;
        "Wyjście") exit 0 ;;
        *) echo -e "${RED}Błędny wybór.${NC}" ;;
    esac
done

# --- 3. WYBÓR PLIKU Z LISTY ---
if [[ ! -d "$SOURCE_DIR" ]]; then
    echo -e "${RED}Błąd: Katalog $SOURCE_DIR nie istnieje!${NC}"
    exit 1
fi

# Pobranie listy plików .tar.gz posortowanych od najnowszych
mapfile -t backup_files < <(ls -t1 "$SOURCE_DIR"/backup_*.tar.gz 2>/dev/null)

if [ ${#backup_files[@]} -eq 0 ]; then
    echo -e "${RED}Błąd: Nie znaleziono żadnych plików backupu w $SOURCE_DIR${NC}"
    exit 1
fi

echo -e "\n${BLUE}Dostępne kopie zapasowe (od najnowszych):${NC}"
for i in "${!backup_files[@]}"; do
    # Wyświetlamy tylko nazwę pliku i jego rozmiar
    size=$(du -sh "${backup_files[$i]}" | awk '{print $1}')
    printf "${YELLOW}[%d]${NC} %-35s (%s)\n" "$i" "$(basename "${backup_files[$i]}")" "$size"
done

echo -e "\n${YELLOW}Wybierz numer backupu do przywrócenia (lub 'q' aby wyjść):${NC}"
read -p "Numer: " selection

if [[ "$selection" == "q" ]]; then
    exit 0
fi

# Sprawdzenie czy wybór jest poprawnym numerem
if [[ ! "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -ge "${#backup_files[@]}" ]; then
    echo -e "${RED}Błędny wybór numeru.${NC}"
    exit 1
fi

SELECTED_FILE="${backup_files[$selection]}"

# --- 4. PRZYWRACANIE ---
echo -e "\n${YELLOW}Wybrałeś: $(basename "$SELECTED_FILE")${NC}"
echo -e "${RED}UWAGA: Operacja nadpisze istniejące pliki w $REAL_HOME!${NC}"
read -p "Czy kontynuować? (wpisz TAK): " confirm

if [[ "$confirm" == "TAK" ]]; then
    echo -e "${BLUE}Przywracanie danych... Proszę czekać.${NC}"
    
    cd "$REAL_HOME"
    
    if tar -xvzf "$SELECTED_FILE"; then
        # Przywracanie uprawnień dla wypakowanych plików
        echo -e "${BLUE}Naprawianie uprawnień...${NC}"
        # Pobieramy listę elementów z tar i zmieniamy właściciela
        tar -tf "$SELECTED_FILE" | xargs chown "$REAL_USER:$REAL_USER" 2>/dev/null || true
        
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}SUKCES! Dane zostały przywrócone.${NC}"
        echo -e "Z pliku: $(basename "$SELECTED_FILE")"
        echo -e "${GREEN}========================================${NC}"
    else
        echo -e "${RED}Wystąpił błąd podczas rozpakowywania.${NC}"
        exit 1
    fi
else
    echo "Anulowano przywracanie."
fi
