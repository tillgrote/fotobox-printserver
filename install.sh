#!/bin/bash
# Richtet einen Raspberry Pi als Fotobox-PrintServer fuer den DNP DS620 ein.
# Kann beliebig oft laufen; "--update" ueberspringt die Rueckfragen.
#
#   sudo bash /opt/fotobox-printserver/install.sh
set -euo pipefail
MODE="${1:-}"
[ "$(id -u)" = 0 ] || exec sudo -E bash "$0" "$@"
HERE="$(cd "$(dirname "$0")" && pwd)"
FILES="$HERE/files"
say() { echo; echo "== $* =="; }

# --- 1. Pakete -------------------------------------------------------------
NEEDED="cups cups-filters ghostscript printer-driver-gutenprint avahi-daemon dnsmasq-base python3 git rsync"
MISSING=""
for package in $NEEDED; do
  dpkg -s "$package" >/dev/null 2>&1 || MISSING="$MISSING $package"
done
if [ -n "$MISSING" ]; then
  say "Installiere Pakete:$MISSING"
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y $MISSING
fi
if ! systemctl is-active --quiet NetworkManager; then
  echo "Hinweis: NetworkManager laeuft nicht. Die WLAN-Seite braucht ihn (Raspberry Pi OS ab Bookworm)."
fi

# --- 2. CUPS ---------------------------------------------------------------
say "CUPS einrichten"
systemctl enable --now cups avahi-daemon
cupsctl --share-printers
LOGIN_USER="${SUDO_USER:-}"
if [ -n "$LOGIN_USER" ] && id "$LOGIN_USER" >/dev/null 2>&1; then
  usermod -aG lpadmin "$LOGIN_USER"
fi

# --- 3. Vorgeschaltetes Backend (Schnitt fuer den 5,6-cm-Streifen) ----------
say "Backend fuer den Streifenschnitt"
BACKEND=/usr/lib/cups/backend/gutenprint53+usb
REAL=/usr/lib/cups/backend-real/gutenprint53+usb
mkdir -p /usr/lib/cups/backend-real
if ! dpkg-divert --list "$BACKEND" | grep -q .; then
  if [ -f "$REAL" ] && head -c 2 "$BACKEND" 2>/dev/null | grep -q '#!'; then
    # Von Hand eingerichteter Pi: Original liegt schon in backend-real.
    dpkg-divert --add --no-rename --divert "$REAL" "$BACKEND"
  else
    dpkg-divert --add --rename --divert "$REAL" "$BACKEND"
  fi
fi
if [ ! -f "$REAL" ]; then
  echo "Das Original-Backend $REAL fehlt. Ist printer-driver-gutenprint installiert? Abbruch."
  exit 1
fi
install -o root -g root -m "$(stat -c %a "$REAL")" "$FILES/gutenprint53+usb-wrapper" "$BACKEND"

# --- 4. Skripte und Dienste -------------------------------------------------
say "Skripte und Dienste"
install -m 755 "$FILES/fotobox-wifi" "$FILES/fotobox-printer" "$FILES/fotobox-update" \
  "$FILES/fotobox-ppd" "$FILES/fotobox-firstboot" /usr/local/sbin/
install -m 644 "$FILES"/fotobox-*.service /etc/systemd/system/
mkdir -p /var/lib/fotobox
systemctl daemon-reload
systemctl enable fotobox-printer.service fotobox-firstboot.service

# --- 5. Einrichtungs-WLAN ---------------------------------------------------
if [ ! -s /etc/fotobox-wifi.conf ]; then
  PW="${AP_PASSWORD:-}"
  if [ -z "$PW" ] && [ "$MODE" != "--update" ] && [ -t 0 ]; then
    while true; do
      read -r -p "Passwort fuer das Einrichtungs-WLAN (8 bis 63 Zeichen): " PW
      [ ${#PW} -ge 8 ] && [ ${#PW} -le 63 ] && break
      echo "Bitte 8 bis 63 Zeichen."
    done
  fi
  if [ ${#PW} -ge 8 ]; then
    printf 'AP_SSID=%s-Setup\nAP_PASSWORD=%s\n' "$(hostname)" "$PW" > /etc/fotobox-wifi.conf
    chmod 600 /etc/fotobox-wifi.conf
  else
    echo "Hinweis: /etc/fotobox-wifi.conf fehlt. Ohne Passwort gibt es kein Einrichtungs-WLAN."
    echo "         Nachholen: sudo AP_PASSWORD=... bash $HERE/install.sh"
  fi
fi
if ss -ltn 2>/dev/null | grep -q ':80 ' && ! systemctl is-active --quiet fotobox-wifi; then
  echo "Hinweis: Port 80 ist schon belegt, die PrintServer-Seite wird nicht gestartet:"
  ss -ltnp | grep ':80 ' || true
else
  systemctl enable fotobox-wifi.service
  systemctl restart fotobox-wifi.service
fi

# --- 6. Stand merken, Drucker einrichten ------------------------------------
if git -C "$HERE" rev-parse --short HEAD >/dev/null 2>&1; then
  git -C "$HERE" log -1 --format='%h vom %cd' --date=format:'%d.%m.%Y' > /etc/fotobox-printserver.version
else
  echo "ohne Git eingerichtet am $(date '+%d.%m.%Y')" > /etc/fotobox-printserver.version
fi
systemctl restart --no-block fotobox-printer.service

say "Fertig"
echo "Stand:  $(cat /etc/fotobox-printserver.version)"
echo "Seite:  http://$(hostname).local/"
echo "Der Drucker wird eingerichtet, sobald er per USB angeschlossen und eingeschaltet ist"
echo "(Verlauf: journalctl -u fotobox-printer)."
if [ "$HERE" != /opt/fotobox-printserver ]; then
  echo "Hinweis: Der Update-Knopf erwartet die Skripte unter /opt/fotobox-printserver."
fi
