#!/usr/bin/env bash
set -euo pipefail

# --- 0. SPRAWDZENIE UPRAWNIEŃ SUDO ---
if [[ $EUID -ne 0 ]]; then
   echo -e "\033[0;31mBŁĄD: Ten skrypt musi być uruchomiony z sudo!\033[0m"
   echo -e "Użyj: \033[0;32msudo $0\033[0m"
   exit 1
fi

# --- 1. WYKRYWANIE UŻYTKOWNIKA ---
REAL_USER=${SUDO_USER:-$USER}
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

# --- 2. KONFIGURACJA ŚCIEŻEK ---
LIST_FILE="$REAL_HOME/.backup_list"
LOCAL_BACKUP_DEST="$REAL_HOME/Backups"
DATE=$(date +%Y-%m-%d_%H-%M)
BACKUP_NAME="backup_$DATE.tar.gz"

BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# --- 3. LOGIKA USB ---
prepare_usb() {
    local dev_node=$1
    local expected_label="backup"
    local target_mount="/media/$REAL_USER/$expected_label"

    if [ ! -b "$dev_node" ]; then
        echo -e "${RED}Błąd: Urządzenie $dev_node nie istnieje.${NC}"; exit 1
    fi

    local current_label=$(lsblk -no LABEL "$dev_node" | head -n 1 || echo "")

    if [[ "$current_label" != "$expected_label" ]]; then
        echo -e "${YELLOW}[!] Wymagane przygotowanie dysku (Etykieta: '$current_label').${NC}"
        read -p "Sformatować $dev_node jako ext4 z nazwą '$expected_label'? (wpisz TAK): " confirm
        [[ "$confirm" != "TAK" ]] && exit 1

        echo -e "${BLUE}Formatowanie...${NC}"
        umount "${dev_node}"* 2>/dev/null || true
        mkfs.ext4 -F -L "$expected_label" "$dev_node"
        partprobe "$dev_node"
        sleep 2
    fi

    if ! findmnt -rnvo TARGET "$dev_node" | grep -q "$target_mount"; then
        mkdir -p "$target_mount"
        umount "$target_mount" 2>/dev/null || true
        mount "$dev_node" "$target_mount"
        chown "$REAL_USER:$REAL_USER" "$target_mount"
    fi
    DEST="$target_mount"
}

# --- 4. WYBÓR MIEJSCA (Z WIDOCZNĄ ŚCIEŻKĄ /media/...) ---
select_destination() {
    echo -e "${BLUE}Użytkownik: $REAL_USER | Katalog: $REAL_HOME${NC}"
    echo -e "${BLUE}Wybierz cel backupu:${NC}"
    options=("Lokalnie" "Pendrive" "Wyjście")
    select opt in "${options[@]}"; do
        case $opt in
            "Lokalnie") 
                DEST="$LOCAL_BACKUP_DEST"
                mkdir -p "$DEST"
                chown "$REAL_USER:$REAL_USER" "$DEST"
                break ;;
            "Pendrive")
                local sys_drive=$(lsblk -no PKNAME $(findmnt -nvo SOURCE /) | head -n 1)
                echo -e "\n${BLUE}Dostępne dyski zewnętrzne:${NC}"
                
                # Nagłówek tabeli - dodana kolumna PUNKT MONTOWANIA
                printf "${YELLOW}%-12s %-8s %-15s %-30s${NC}\n" "URZĄDZENIE" "ROZMIAR" "MODEL" "PUNKT MONTOWANIA"
                echo "--------------------------------------------------------------------------------"
                
                # Pobieranie danych: nazwa, rozmiar, model, punkt montowania
                lsblk -dno NAME,SIZE,MODEL,MOUNTPOINT | grep -v "loop" | grep -v "$sys_drive" | while read -r name size model mount; do
                    # Jeśli punkt montowania jest pusty, wyświetlamy czytelną informację
                    local display_mount=${mount:-"[NIEZAMONTOWANY]"}
                    printf "/dev/%-7s %-8s %-15s %-30s\n" "$name" "$size" "$model" "$display_mount"
                done
                
                echo -e "\n${YELLOW}Wpisz nazwę (np. sda) lub pełną ścieżkę (np. /dev/sda):${NC}"
                read -p "Wybór: " dev_input
                
                # Auto-uzupełnianie /dev/
                [[ "$dev_input" != /dev/* ]] && dev_input="/dev/$dev_input"
                
                prepare_usb "$dev_input"
                break ;;
            "Wyjście") exit 0 ;;
            *) echo -e "${RED}Błąd wyboru.${NC}" ;;
        esac
    done
}

# --- 5. WYKONANIE ---
perform_backup() {
    select_destination
    
    local items=("Obsidian" "Scripts" ".bash_aliases" ".backup_list" ".vimrc")
    if [[ -s "$LIST_FILE" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
            items+=("$line")
        done < "$LIST_FILE"
    fi

    cd "$REAL_HOME"
    local valid=()
    echo -e "\n${BLUE}Weryfikacja plików...${NC}"
    for i in "${items[@]}"; do
        [[ -e "$i" ]] && valid+=("$i") || echo -e "${RED}[!] Pominięto: $REAL_HOME/$i${NC}"
    done

    [[ ${#valid[@]} -eq 0 ]] && { echo -e "${RED}Błąd: Brak plików!${NC}"; exit 1; }

    echo -e "${BLUE}Tworzenie archiwum w: $DEST${NC}"
    if tar -czf "$DEST/$BACKUP_NAME" "${valid[@]}"; then
        sync
        chown "$REAL_USER:$REAL_USER" "$DEST/$BACKUP_NAME"
        
        local free_space=$(df -h "$DEST" | awk 'NR==2 {print $4}')
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}SUKCES! Backup zapisany.${NC}"
        echo -e "Ścieżka docelowa: $DEST/$BACKUP_NAME"
        echo -e "Pozostałe miejsce: $free_space"
        echo -e "${GREEN}========================================${NC}"
    else
        echo -e "${RED}Błąd tar.${NC}"; exit 1
    fi
}

perform_backup
