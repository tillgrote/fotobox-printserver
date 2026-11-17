# Fotobox-PrintServer

Macht aus einem Raspberry Pi einen AirPrint-Druckserver für Fotodrucker von
DNP, so dass die Fotobox-App auf dem iPad drucken kann.

Der Pi hängt per USB am Drucker und per WLAN im selben Netz wie das iPad.

## Drucker

Erkannt wird jeder DNP-Drucker, für den das installierte Gutenprint einen
Treiber hat. Das Modell liest der Pi vom USB ab.

| Drucker | 10×15 | Streifen | Stand |
|---|---|---|---|
| DS620 | ja | 5 cm und 5,6 cm, vom Drucker geschnitten | getestet |
| QW410 | ja, mit 4-Zoll-Papier | nein | nicht getestet |
| DS40, DS-RX1 | ja | nein | nicht getestet |
| DS80, DS80DX, DS820 | kein 10×15 (8-Zoll-Drucker) | nein | nicht getestet |

Zu den nicht getesteten Modellen: Die Anpassung der Papierformate ist für sie
nur an nachgebauten PPDs aus dem Gutenprint-Quelltext geprüft, nicht am Gerät.
Ob das Gutenprint des Betriebssystems ein Modell kennt, zeigt
`lpinfo -m | grep -i dnp`; fehlt der Treiber, meldet `fotobox-printer` das im
Protokoll.

Beim QW410 bleiben nur die Formate für 4 Zoll breites Papier. Mit 4,5 Zoll
breitem Papier druckt er über diesen Server nicht.

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
   Warteschlange entsteht dann von selbst, spätestens nach 30 Sekunden, und
   heißt wie das Modell (`DS620`, `QW410` ...).
5. **Auf dem iPad** in der Fotobox-App unter Admin > Druck den Drucker wählen.

## Was eingerichtet wird

| Teil | Zweck |
|---|---|
| CUPS, Gutenprint, Avahi | Druckdienst, Treiber, AirPrint-Bekanntgabe |
| `fotobox-printer` | legt die Warteschlange für den angeschlossenen DNP-Drucker an und passt deren PPD an |
| `fotobox-ppd` | macht die Papierformate für iOS unterscheidbar (siehe unten) |
| vorgeschaltetes Backend | schneidet beim DS620 den 5,6-cm-Streifen bei 2,2 Zoll |
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

iOS unterscheidet Papiere nur nach ihren Maßen. In den Gutenprint-PPDs haben
oft mehrere Formate dieselben Maße: neben dem einfachen Format die Varianten,
die der Drucker aus demselben Feld schneidet (z. B. 4x6 und 2x6*2). Ohne
Anpassung landet ein Druck vom iPad auf dem falschen Format.

`fotobox-ppd` lässt deshalb von allen Formaten mit gleichen Maßen nur eines
übrig: 4x6 (`w288h432`), wenn es dabei ist, sonst das erste einfache Format.

Ausnahme DS620, damit der Drucker Streifen schneiden kann:

| Format | Änderung |
|---|---|
| `w288h432` (4x6) | bleibt, wird Standard |
| `w144h432` (2x6) | bleibt, Blattlänge 468,0 pt statt 460,8 |
| `w243h432` (3.375x6) | bleibt, Blattlänge 475,2 pt; Träger für den 5,6-cm-Streifen |

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

- Nur DNP-Drucker über Gutenprint.
- Die Streifenvorlagen der App funktionieren nur mit dem DS620. Die Lage der
  Streifen auf dem Papier ist in der App an einem einzelnen DS620 gemessen.
- Ein Update von Gutenprint kann eine neu erzeugte PPD verändern.
  `fotobox-printer` passt sie beim nächsten Start wieder an.
