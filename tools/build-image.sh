#!/bin/bash
# Baut aus dem laufenden PrintServer ein kleines Basis-Abbild: /var/tmp/printserver.img
# Das Abbild enthaelt keine WLAN-Zugangsdaten, keine Druckauftraege und keine
# SSH-Schluessel. Es enthaelt weiter das Benutzerkonto und das Passwort des
# Einrichtungs-WLANs. Die laufende Karte wird nur gelesen.
#
# Beim ersten Start einer Karte aus diesem Abbild laeuft fotobox-firstboot.
set -euo pipefail
[ "$(id -u)" = 0 ] || exec sudo bash "$0" "$@"

IMG=/var/tmp/printserver.img
MNT=/mnt/printserver-img
BOOT_MB=512

ROOTDEV=$(findmnt -no SOURCE /)
DISK=/dev/$(lsblk -no PKNAME "$ROOTDEV")
DISKID=$(sfdisk --disk-id "$DISK")
if ! grep -q "PARTUUID=${DISKID#0x}-02" /etc/fstab; then
  echo "Die fstab nutzt nicht PARTUUID=${DISKID#0x}-02. Abbruch, nichts wurde geaendert."
  exit 1
fi
for tool in rsync mkfs.vfat mkfs.ext4 sfdisk losetup; do
  if ! command -v "$tool" >/dev/null; then
    apt-get install -y rsync dosfstools e2fsprogs fdisk
    break
  fi
done

rm -f "$IMG"
USED=$(df --output=used -BM / | tail -1 | tr -dc 0-9)
SIZE=$(( USED + USED / 8 + 1024 + BOOT_MB ))
FREE=$(df --output=avail -BM /var/tmp | tail -1 | tr -dc 0-9)
if [ "$FREE" -lt $(( SIZE + 500 )) ]; then
  echo "Zu wenig Platz: gebraucht ${SIZE} MB, frei ${FREE} MB. Abbruch."
  exit 1
fi
echo "Abbild wird ${SIZE} MB gross (belegt sind ${USED} MB)."

LOOP=""
cleanup() {
  set +e
  mountpoint -q "$MNT/boot/firmware" && umount "$MNT/boot/firmware"
  mountpoint -q "$MNT" && umount "$MNT"
  [ -n "$LOOP" ] && losetup -d "$LOOP"
  systemctl start cups
}
trap cleanup EXIT

truncate -s "${SIZE}M" "$IMG"
printf 'label: dos\nlabel-id: %s\nstart=8192, size=%s, type=c\nstart=%s, type=83\n' \
  "$DISKID" $(( BOOT_MB * 2048 )) $(( 8192 + BOOT_MB * 2048 )) | sfdisk -q "$IMG"
LOOP=$(losetup --show -fP "$IMG")
mkfs.vfat -F 32 -n bootfs "${LOOP}p1" >/dev/null
mkfs.ext4 -q -F -L rootfs "${LOOP}p2"
mkdir -p "$MNT"
mount "${LOOP}p2" "$MNT"
mkdir -p "$MNT/boot/firmware"
mount "${LOOP}p1" "$MNT/boot/firmware"

echo "Kopiere das System (einige Minuten) ..."
systemctl stop cups
rsync -aHAXx --numeric-ids \
  --exclude='/var/tmp/*' --exclude='/tmp/*' \
  --exclude='/var/spool/cups/[cd]*' --exclude='/var/spool/cups/tmp/*' \
  --exclude='/var/log/journal/*' --exclude='/var/log/cups/*' \
  --exclude='/var/cache/apt/archives/*.deb' \
  --exclude='/home/*/.bash_history' --exclude='/root/.bash_history' \
  --exclude='/etc/ssh/ssh_host_*' \
  --exclude='/etc/NetworkManager/system-connections/*' \
  --exclude='/etc/netplan/*.yaml' \
  / "$MNT/"
systemctl start cups
rsync -rt --exclude='/network-config' /boot/firmware/ "$MNT/boot/firmware/"

# Das Abbild neutral machen
: > "$MNT/etc/machine-id"
rm -f "$MNT/var/lib/dbus/machine-id"
mkdir -p "$MNT/etc/cloud"
touch "$MNT/etc/cloud/cloud-init.disabled"
touch "$MNT/etc/fotobox-firstboot"
sync

cleanup
trap - EXIT
LOOP=""
ls -lh "$IMG"
echo "Fertig: $IMG"
echo "Auf den Rechner holen:  ssh <benutzer>@<name> 'gzip -1 -c $IMG' > printserver.img.gz"
