# Fotobox-PrintServer

Macht aus einem Raspberry Pi einen AirPrint-Druckserver für den DNP DS620, so
dass die Fotobox-App auf dem iPad 10×15-Bilder und Fotostreifen drucken kann.

Der Pi hängt per USB am Drucker und per WLAN im selben Netz wie das iPad.

## Stand

- Entstanden und getestet auf einem **Raspberry Pi 4** mit Raspberry Pi OS
  Trixie (Debian 13), CUPS und Gutenprint 5.3.4. Dort wurden die einzelnen
  Schritte von Hand eingerichtet.
- Das Einrichtungsskript `install.sh` fasst diese Schritte zusammen. **Als
  Ganzes ist es noch auf keinem Pi gelaufen**, auch nicht auf einem Pi Zero 2 W.
- Getestet auf dem Pi 4: die WLAN-Seite und der Streifenschnitt.

## Neuen Pi einrichten

1. **Karte beschreiben:** Mit einem aktuellen Raspberry Pi Imager „Raspberry Pi
   OS Lite (64-bit)" auf die Karte schreiben. In den Einstellungen des Imagers
   Namen (z. B. `PrintServer`), Benutzer, das eigene WLAN samt WLAN-Land und SSH
   einschalten.
2. **Anmelden:** Pi starten, dann vom Rechner aus `ssh <benutzer>@<name>.local`.
3. **Einrichten:**

   ```
   sudo apt-get update && sudo apt-get install -y git
   sudo git clone https://github.com/tillgrote/fotobox-printserver /opt/fotobox-printserver
   sudo bash /opt/fotobox-printserver/install.sh
   ```

   Das Skript fragt nach einem Passwort für das Einrichtungs-WLAN. Auf einem Pi
   Zero dauert die Installation der Pakete eine Weile.
4. **Drucker anschließen** (am Pi Zero über ein OTG-Kabel) und einschalten. Die
   Warteschlange `DS620` entsteht dann von selbst, spätestens nach 30 Sekunden.
5. **Auf dem iPad** in der Fotobox-App unter Admin > Druck den Drucker wählen.

## Was eingerichtet wird

| Teil | Zweck |
|---|---|
| CUPS, Gutenprint, Avahi | Druckdienst, Treiber, AirPrint-Bekanntgabe |
| `fotobox-printer` | legt die Warteschlange für den angeschlossenen DS620 an und passt deren PPD an |
| `fotobox-ppd` | macht die Papierformate für iOS unterscheidbar (siehe unten) |
| vorgeschaltetes Backend | schneidet den 5,6-cm-Streifen bei 2,2 Zoll |
| `fotobox-wifi` | Seite zum WLAN-Wechsel und für Updates |
| `fotobox-update` | holt den aktuellen Stand dieses Repos |

## WLAN wechseln

- Im WLAN: `http://<name>.local/` öffnen, neues Netz wählen, Passwort eingeben.
- Ohne bekanntes WLAN öffnet der Pi nach etwa 40 Sekunden das Einrichtungs-WLAN
  `<name>-Setup`. Damit verbinden und `http://10.42.0.1/` öffnen.
- Die Seite hat keine Anmeldung: Jeder im selben WLAN kann sie öffnen.

## Aktualisieren

Auf der Seite des PrintServers auf „Aktualisieren" tippen. Der Pi holt den Stand
des Zweigs `main` und richtet sich damit neu ein. Dafür braucht er ein WLAN mit
Internet. Automatisch aktualisiert er sich nie.

Von Hand: `sudo fotobox-update`, Verlauf in `/var/log/fotobox-update.log`.

In `main` gehört deshalb nur, was auf einem Pi getestet ist.

## Warum die PPD angepasst wird

iOS unterscheidet Papiere nur nach ihren Maßen. In der Gutenprint-PPD haben
mehrere Formate dieselben Maße wie 4x6, nämlich die Streifen, die der Drucker
aus einem 4x6-Feld schneidet. Ohne Anpassung landet ein 10×15-Druck auf dem
falschen Format. `fotobox-ppd` ändert deshalb:

| Format | Änderung |
|---|---|
| `w288h432` (4x6) | bleibt, wird Standard |
| `w144h432` (2x6) | Blattlänge 468,0 pt statt 460,8 |
| `w243h432` (3.375x6) | Blattlänge 475,2 pt; Träger für den 5,6-cm-Streifen |
| alle anderen mit den Maßen von 4x6 | entfernt |

Die Breite der druckbaren Fläche bleibt unverändert, weil der Treiber eine
schmalere Fläche auf seine eigene Breite streckt.

Nach einer Änderung an den Papieren das iPad neu starten und den Drucker in der
App neu wählen; iOS behält die alten Papierdaten sonst.

## Basis-Abbild

`tools/build-image.sh` baut aus einem fertig eingerichteten Pi ein kleines
Abbild ohne WLAN-Daten, Druckaufträge und SSH-Schlüssel. Das Benutzerkonto und
das Passwort des Einrichtungs-WLANs bleiben darin. Eine Karte aus diesem Abbild
gibt sich beim ersten Start einen eigenen Namen (`fotobox-firstboot`). Noch
nicht getestet.

## Grenzen

- Nur DNP DS620 über Gutenprint.
- Die Lage der Streifen auf dem Papier ist in der App an einem einzelnen DS620
  gemessen.
- Ein Update von Gutenprint kann eine neu erzeugte PPD verändern.
  `fotobox-printer` passt sie beim nächsten Start wieder an.
