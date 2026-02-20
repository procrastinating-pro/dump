#!/bin/bash

# --- KONFIGURACJA ---
SCRIPTS_DIR="$HOME/Scripts"
SCRIPT_PATH="$SCRIPTS_DIR/update_qflipper.sh"
APPS_DIR="$HOME/Apps/qFlipper"
EXTRACT_DIR="$APPS_DIR/extracted"
ALIAS_FILE="$HOME/.bash_aliases"
URL="https://update.flipperzero.one/qFlipper/release/linux-amd64/AppImage"

# 1. AUTOKOPIOWANIE DO ~/Scripts
mkdir -p "$SCRIPTS_DIR"
if [[ "$(realpath "$0")" != "$(realpath "$SCRIPT_PATH")" ]]; then
    cp "$0" "$SCRIPT_PATH"
    chmod +x "$SCRIPT_PATH"
    echo "Skrypt zainstalował się w: $SCRIPT_PATH"
fi

# 2. FUNKCJA AKTUALIZACJI ALIASÓW
update_aliases() {
    touch "$ALIAS_FILE"
    
    # Alias 1: Uruchamianie (nohup + sudo + tło)
    # Używamy pełnej ścieżki bez zmiennych środowiskowych wewnątrz aliasu dla stabilności
    RUN_ALIAS="alias qflipper='nohup sudo $EXTRACT_DIR/AppRun > /dev/null 2>&1 &'"
    
    # Alias 2: Aktualizacja (wywołanie tego skryptu)
    UPDATE_ALIAS="alias qflipper-update='$SCRIPT_PATH'"

    # Usuwamy stare aliasy qflipper, jeśli istnieją, i dodajemy nowe
    sed -i '/alias qflipper=/d' "$ALIAS_FILE"
    sed -i '/alias qflipper-update=/d' "$ALIAS_FILE"
    
    echo "$RUN_ALIAS" >> "$ALIAS_FILE"
    echo "$UPDATE_ALIAS" >> "$ALIAS_FILE"
    
    echo "Aliasy zostały skonfigurowane w $ALIAS_FILE:"
    echo "  - 'qflipper'        -> uruchamia program"
    echo "  - 'qflipper-update' -> sprawdza aktualizacje"
}

# 3. SPRAWDZANIE AKTUALIZACJI
mkdir -p "$APPS_DIR"
TEMP_APPIMAGE="$APPS_DIR/qFlipper-latest.AppImage"
MARKER="$APPS_DIR/.last_etag"

echo "Sprawdzanie dostępności aktualizacji na serwerze..."
# Pobranie ETag (identyfikator wersji na serwerze)
NEW_ETAG=$(curl -sI "$URL" | grep -i etag | awk '{print $2}' | tr -d '\r\n')

if [ -f "$MARKER" ] && [ "$(cat "$MARKER")" == "$NEW_ETAG" ] && [ -d "$EXTRACT_DIR" ]; then
    echo "Twoja wersja qFlipper jest już aktualna."
    update_aliases
    exit 0
fi

# 4. POBIERANIE I EKSTRAKCJA
echo "Dostępna nowa wersja qFlipper."
read -p "Czy chcesz ją pobrać i wypakować? (y/N): " choice
if [[ "$choice" =~ ^[yY]$ ]]; then
    echo "Pobieranie..."
    if wget -q --show-progress -O "$TEMP_APPIMAGE" "$URL"; then
        chmod +x "$TEMP_APPIMAGE"
        
        echo "Wypakowywanie..."
        rm -rf "$EXTRACT_DIR"
        cd "$APPS_DIR" || exit 1
        
        # Ekstrakcja AppImage
        if "$TEMP_APPIMAGE" --appimage-extract > /dev/null 2>&1; then
            mv squashfs-root "$EXTRACT_DIR"
            rm "$TEMP_APPIMAGE"
            echo "$NEW_ETAG" > "$MARKER"
            echo "Sukces: Program zaktualizowany i wypakowany."
            update_aliases
        else
            echo "Błąd: Ekstrakcja się nie powiodła (sprawdź libfuse2)."
            exit 1
        fi
    else
        echo "Błąd: Pobieranie nie powiodło się."
        exit 1
    fi
else
    echo "Anulowano aktualizację plików."
    update_aliases
fi

echo "Gotowe. Wpisz 'source $ALIAS_FILE', aby odświeżyć aliasy w tej sesji."
