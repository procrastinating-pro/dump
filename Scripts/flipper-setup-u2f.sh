#!/bin/bash

# Sprawdzenie roota
if [ "$EUID" -ne 0 ]; then
  sudo "$0" "$@"
  exit $?
fi

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Konfiguracja Flipper U2F: Sudo + Logowanie do Pulpitu ===${NC}"

# 1. Rejestracja klucza (jeśli jeszcze nie zrobiona)
USER_HOME=$(eval echo "~$SUDO_USER")
mkdir -p "$USER_HOME/.config/Yubico"

if [ ! -f "$USER_HOME/.config/Yubico/u2f_keys" ]; then
    echo -e "\n${GREEN}Rejestracja nowo wykrytego Flippera...${NC}"
    pamu2f-cfg -u "$SUDO_USER" > "$USER_HOME/.config/Yubico/u2f_keys"
    chown -R "$SUDO_USER:$SUDO_USER" "$USER_HOME/.config/Yubico"
else
    echo -e "Klucze U2F już istnieją w Twoim profilu."
fi

# 2. Funkcja dodająca regułę do pliku PAM
configure_pam() {
    local FILE=$1
    local RULE="auth sufficient pam_u2f.so"
    local TARGET="@include common-auth"

    if [ -f "$FILE" ]; then
        echo -e "Konfiguruję plik: $FILE"
        # Usuwamy stare reguły u2f
        sed -i '/pam_u2f.so/d' "$FILE"
        # Wstawiamy nową nad TARGET
        sed -i "/$TARGET/i $RULE" "$FILE"
    fi
}

# 3. Zastosowanie zmian dla sudo i ekranu logowania (GDM)
configure_pam "/etc/pam.d/sudo"
configure_pam "/etc/pam.d/gdm-password"

# Dodatkowo dla ekranu blokady (jeśli używasz skrótu Super+L)
configure_pam "/etc/pam.d/gnome-screensaver"

echo -e "\n${GREEN}KONFIGURACJA ZAKOŃCZONA!${NC}"
echo -e "Teraz możesz logować się do pulpitu samym przyciskiem na Flipperze."
