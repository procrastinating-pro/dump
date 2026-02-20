#!/usr/bin/env bash

set -euo pipefail

# --- Konfiguracja Użytkownika ---
# Wykrywamy użytkownika, który uruchomił sudo, aby nie pobierać do /root
REAL_USER=${SUDO_USER:-$USER}
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
DOWNLOAD_DIR="$REAL_HOME/Downloads"

BASE_URL="https://releases.ubuntu.com"
BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# --- Funkcja wykrywająca dysk systemowy ---
get_system_drive() {
    # Znajduje dysk nadrzędny dla głównego montowania /
    lsblk -no PKNAME $(findmnt -nvo SOURCE /) | head -n 1
}

# --- 1. Sprawdzanie uprawnień SUDO ---
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Błąd: Skrypt musi być uruchomiony z sudo (aby mieć dostęp do /dev/sdX).${NC}"
   exit 1
fi

# Tworzymy katalog jako root, ale zaraz zmienimy właściciela
mkdir -p "$DOWNLOAD_DIR"
chown "$REAL_USER:$REAL_USER" "$DOWNLOAD_DIR"

SYS_DRIVE=$(get_system_drive)

echo -e "${BLUE}== Ubuntu Safe Downloader & USB Tool ==${NC}"
echo -e "${BLUE}Użytkownik: $REAL_USER | Katalog: $DOWNLOAD_DIR${NC}"
echo -e "${BLUE}Wykryty dysk systemowy: /dev/$SYS_DRIVE (ZABLOKOWANY)${NC}\n"

# --- 2. Wybór wersji i wariantu ---
echo -e "${BLUE}Pobieranie listy wersji...${NC}"
mapfile -t VERSIONS < <(curl -s "$BASE_URL/" | grep -oP 'href="\K[a-z0-9.]+(?=/")' | grep -E '^[0-9]{2}\.[0-9]{2}' | sort -V -r -u)

echo -e "${BLUE}KROK 1: Wybierz wersję Ubuntu:${NC}"
select VERSION in "${VERSIONS[@]}"; do
    [[ -n "$VERSION" ]] && break || echo -e "${RED}Błędny wybór.${NC}"
done

echo -e "\n${BLUE}KROK 2: Wybierz wariant:${NC}"
VARIANTS=("Desktop" "Server")
select VARIANT in "${VARIANTS[@]}"; do
    case $VARIANT in
        "Desktop") ISO_PATTERN="desktop-amd64.iso"; break ;;
        "Server") ISO_PATTERN="live-server-amd64.iso"; break ;;
    esac
done

# --- 3. Pobieranie / Sprawdzanie pliku ---
ISO_FILE_NAME=$(curl -s "$BASE_URL/$VERSION/" | grep -oP "href=\"\Kubuntu-[0-9.]+-${ISO_PATTERN}" | head -n 1)
FULL_PATH="$DOWNLOAD_DIR/$ISO_FILE_NAME"

if [[ ! -f "$FULL_PATH" ]]; then
    echo -e "\n${BLUE}[INFO] Pobieranie $ISO_FILE_NAME...${NC}"
    # Pobieramy jako root, ale z flagą zachowania uprawnień lub późniejszą zmianą
    wget --show-progress -O "$FULL_PATH" "$BASE_URL/$VERSION/$ISO_FILE_NAME"
    chown "$REAL_USER:$REAL_USER" "$FULL_PATH"
else
    echo -e "\n${GREEN}[INFO] Plik już istnieje: $FULL_PATH${NC}"
fi

# --- 4. Checksum ---
echo -e "\n${BLUE}[INFO] Weryfikacja SHA256...${NC}"
REMOTE_SHA=$(curl -s "$BASE_URL/$VERSION/SHA256SUMS" | grep "$ISO_FILE_NAME" | awk '{print $1}')
LOCAL_SHA=$(sha256sum "$FULL_PATH" | awk '{print $1}')

if [[ "$REMOTE_SHA" != "$LOCAL_SHA" ]]; then
    echo -e "${RED}[ALARM] Suma kontrolna błędna!${NC}"
    echo "Oczekiwano: $REMOTE_SHA"
    echo "Otrzymano:  $LOCAL_SHA"
    read -p "Kontynuować mimo to? (y/n): " FORCE && [[ ! "$FORCE" =~ ^[Yy]$ ]] && exit 1
else
    echo -e "${GREEN}[OK] Plik jest poprawny.${NC}"
fi

# --- 5. Sekcja USB ---
echo -e "\n------------------------------------------"
read -p "Czy chcesz utworzyć bootowalny pendrive? (y/n): " MAKE_USB

if [[ "$MAKE_USB" =~ ^[Yy]$ ]]; then
    echo -e "\n${BLUE}Dostępne urządzenia (wykluczono systemowy /dev/$SYS_DRIVE):${NC}"
    
    # Wyświetlamy tylko fizyczne dyski, pomijając systemowy i pętle
    lsblk -dno NAME,SIZE,MODEL | grep -v "loop" | grep -v "$SYS_DRIVE" || echo "Brak innych dysków!"

    while true; do
        echo -e "\n${RED}Podaj nazwę urządzenia (np. sdb):${NC}"
        read -p "Wybór: /dev/" DISK_NAME
        
        if [[ "$DISK_NAME" == "$SYS_DRIVE" ]]; then
            echo -e "${RED}BŁĄD: /dev/$DISK_NAME to Twój dysk systemowy! Nie zniszcz sobie systemu.${NC}"
        elif [[ "$DISK_NAME" == loop* ]]; then
            echo -e "${RED}BŁĄD: Nie możesz wybrać urządzenia loop.${NC}"
        elif [[ -z "$DISK_NAME" ]]; then
            echo -e "${RED}Nazwa nie może być pusta.${NC}"
        elif [ ! -b "/dev/$DISK_NAME" ]; then
            echo -e "${RED}BŁĄD: /dev/$DISK_NAME nie istnieje.${NC}"
        else
            break
        fi
    done

    TARGET_DEV="/dev/$DISK_NAME"
    
    # Bezpiecznik: Odmontowanie partycji pendrive'a przed zapisem
    echo -e "${BLUE}Odmontowywanie partycji na $TARGET_DEV...${NC}"
    umount ${TARGET_DEV}* 2>/dev/null || true

    echo -e "\n${RED}!!! UWAGA !!!${NC}"
    echo -e "${RED}Wszystkie dane na $TARGET_DEV zostaną BEZPOWROTNIE USUNIĘTE.${NC}"
    read -p "Potwierdź wpisując 'TAK' (wielkimi literami): " FINAL_CONFIRM
    
    if [[ "$FINAL_CONFIRM" == "TAK" ]]; then
        echo -e "${BLUE}Zapisywanie obrazu... To może potrwać kilka minut.${NC}"
        dd if="$FULL_PATH" of="$TARGET_DEV" bs=4M status=progress conv=fdatasync
        sync
        echo -e "\n${GREEN}Sukces! Pendrive Ubuntu ($VERSION $VARIANT) jest gotowy.${NC}"
    else
        echo "Anulowano na żądanie użytkownika."
    fi
fi
