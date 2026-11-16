#!/usr/bin/env bash
# Lab 4 - run INSIDE the Ubuntu guest. It builds a RAID 1 mirror, fails one disk,
# rebuilds with a third disk and saves every command + real output to evidence/.
# WARNING: it ERASES the three extra 2 GB disks (D1, D2, D3). Never point it at the system disk.
set -u
D1=${D1:-sdb}; D2=${D2:-sdc}; D3=${D3:-sdd}
NAME="Shakhzoda Donavan"
cd "$(dirname "$0")" && mkdir -p evidence
run() { echo "\$ $*"; "$@" 2>&1; echo; }

echo "Disks that will be ERASED: /dev/$D1 /dev/$D2 /dev/$D3"
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS
read -r -p "Are these the empty extra disks and NOT the system disk? Type YES: " ok
[ "$ok" = "YES" ] || { echo "Aborted."; exit 1; }

# 0. state before
{ run lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS; } | tee evidence/lsblk-before.txt

# 1. partition two disks, build the mirror
sudo apt install -y mdadm >/dev/null 2>&1
{
  for d in $D1 $D2; do
    run sudo parted -s /dev/$d mklabel gpt mkpart raid 1MiB 100% set 1 raid on
  done
  run sudo mdadm --create /dev/md0 --level=1 --raid-devices=2 --metadata=1.2 --bitmap=internal --run /dev/${D1}1 /dev/${D2}1
  run sudo mkfs.ext4 -L mirror /dev/md0
  run sudo mkdir -p /mnt/mirror
  run sudo mount /dev/md0 /mnt/mirror
  sudo mdadm --wait /dev/md0 || true
  run cat /proc/mdstat
  run sudo mdadm --detail /dev/md0
} | tee evidence/array-healthy.txt

# 2. recognisable files + checksums
{
  echo "\$ write proof.txt and a 100 MB random file"
  echo "Lab 4 - $NAME - written $(date)" | sudo tee /mnt/mirror/proof.txt
  sudo dd if=/dev/urandom of=/mnt/mirror/random-100M.bin bs=1M count=100 2>&1
  sync; echo
  run sha256sum /mnt/mirror/proof.txt /mnt/mirror/random-100M.bin
} | tee evidence/checksum-before.txt

# 3. fail one disk
{
  run sudo mdadm /dev/md0 --fail /dev/${D2}1
  run sudo mdadm /dev/md0 --remove /dev/${D2}1
  run cat /proc/mdstat
  run sudo mdadm --detail /dev/md0
} | tee evidence/array-degraded.txt
{
  run sudo sysctl vm.drop_caches=3
  run sha256sum /mnt/mirror/proof.txt /mnt/mirror/random-100M.bin
} | tee evidence/checksum-after-failure.txt

# 4. add the third disk and rebuild
{
  run sudo parted -s /dev/$D3 mklabel gpt mkpart raid 1MiB 100% set 1 raid on
  run sudo mdadm /dev/md0 --add /dev/${D3}1
  run cat /proc/mdstat
  sleep 3
  run cat /proc/mdstat
  sudo mdadm --wait /dev/md0 || true
  run cat /proc/mdstat
  run sudo mdadm --detail /dev/md0
  run sha256sum /mnt/mirror/proof.txt /mnt/mirror/random-100M.bin
} | tee evidence/array-rebuilt.txt

echo "Done. Real outputs are in ./evidence - take your screenshots now."
