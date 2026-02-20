#!/usr/bin/env bash
set -euo pipefail

# Wykrywanie użytkownika (nawet przy sudo)
REAL_USER=${SUDO_USER:-$USER}
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
LIST_FILE="$REAL_HOME/.backup_list"
CUR_DIR=$(pwd)

# Sprawdzenie czy jesteśmy w katalogu domowym tego użytkownika
if [[ "$CUR_DIR" != "$REAL_HOME"* ]]; then
    echo -e "\033[0;31mBłąd: Możesz dodawać tylko foldery z $REAL_HOME\033[0m"
    exit 1
fi

# Wyciągnięcie relatywnej ścieżki
REL_PATH=${CUR_DIR#$REAL_HOME/}

if [[ -z "$REL_PATH" ]]; then
    echo -e "\033[0;31mBłąd: Nie dodawaj całego katalogu domowego.\033[0m"
    exit 1
fi

[[ -f "$LIST_FILE" ]] || touch "$LIST_FILE"
chown "$REAL_USER:$REAL_USER" "$LIST_FILE"

if grep -Fxq "$REL_PATH" "$LIST_FILE" 2>/dev/null; then
    echo -e "\033[0;31mFolder '$REL_PATH' jest już na liście.\033[0m"
else
    echo "$REL_PATH" >> "$LIST_FILE"
    echo -e "\033[0;32mDodano '$REL_PATH' do .backup_list\033[0m"
fi
