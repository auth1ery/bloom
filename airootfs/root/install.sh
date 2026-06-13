#!/bin/bash

set -e

r="\e[31m" g="\e[32m" y="\e[33m" b="\e[34m" m="\e[35m" c="\e[36m" w="\e[0m"

say()  { echo -e "${b}bloom${w} :: $*"; }
ok()   { echo -e "${g}  ✓${w}  $*"; }
warn() { echo -e "${y}  !${w}  $*"; }
die()  { echo -e "${r}  ✗${w}  $*"; exit 1; }

ask() {
  local var="$1" prompt="$2" default="$3"
  if [ -n "$default" ]; then
    read -rp "$(echo -e "${c}  ?${w}  $prompt [${y}$default${w}]: ")" val
    eval "$var=\"${val:-$default}\""
  else
    read -rp "$(echo -e "${c}  ?${w}  $prompt: ")" val
    while [ -z "$val" ]; do
      echo -e "${r}  ✗${w}  required"
      read -rp "$(echo -e "${c}  ?${w}  $prompt: ")" val
    done
    eval "$var=\"$val\""
  fi
}

confirm() {
  read -rp "$(echo -e "${y}  ?${w}  $1 [y/N]: ")" yn
  [[ "$yn" =~ ^[Yy]$ ]]
}

show_disks() {
  echo ""
  echo -e "  ${w}available disks:${w}"
  echo ""
  lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep -v loop
  echo ""
  echo -e "  ${c}unallocated space:${w}"
  FOUND_FREE=false
  for d in $(lsblk -dno NAME | grep -v loop); do
    while IFS= read -r line; do
      FOUND_FREE=true
      echo "  /dev/$d: $line"
    done < <(parted --script /dev/$d unit GiB print free 2>/dev/null \
      | awk '/Free Space/ { printf "%s free (%s - %s)\n", $3, $1, $2 }')
  done
  if [ "$FOUND_FREE" = false ]; then
    echo -e "  ${y}none found${w}"
  fi
  echo ""
}

clear
echo -e "${m}"
cat << 'EOF'
      _._
   .-( * )-.
  ( *  *  * )
   '-( * )-'
      `-'

        bloom installer script
	an arch-based distro by auth
	<3

EOF
echo -e "${w}"
echo -e "  ${y}defaults are shown in yellow. press enter to accept them!${w}"
echo -e "  ${y}choose options carefully!${w}"
echo ""

say "starting install!"
echo ""

timedatectl set-ntp true
ok "ntp enabled"

echo ""
say "disk setup"

show_disks

WIPE=false
AUTOPART=false

echo -e "  ${y}!${w}  do you want to wipe a disk entirely, or keep existing data?"
echo -e "  ${w}  1) wipe entire disk  (default)${w}"
echo -e "  ${w}  2) keep existing data / manual setup${w}"
echo ""
ask WIPEMODE "wipe or keep" "1"

if [ "$WIPEMODE" = "1" ]; then

  ask DISK "target disk (e.g. sda, nvme0n1)"
  DISK="/dev/$DISK"
  [ -b "$DISK" ] || die "$DISK is not a block device"

  if [[ "$DISK" == *"nvme"* ]]; then
    PART_EFI="${DISK}p1"
    PART_ROOT="${DISK}p2"
  else
    PART_EFI="${DISK}1"
    PART_ROOT="${DISK}2"
  fi

  WIPE=true

  echo ""
  warn "this will WIPE $DISK entirely. all data will be lost!"
  confirm "are you sure?" || die "aborted"

else

  echo ""
  echo -e "  ${y}!${w}  how do you want to set up partitions?"
  echo -e "  ${w}  1) use existing partitions  (default)${w}"
  echo -e "  ${w}  2) use unallocated space (auto-partition)${w}"
  echo -e "  ${w}  3) manually manage partitions with cfdisk${w}"
  echo ""
  ask PARTMODE "partition setup" "1"

  if [ "$PARTMODE" = "1" ]; then

    warn "make sure the partition is unmounted and has enough space (at least 20G recommended)"
    ask PART_ROOT "target partition for root (e.g. sda2, nvme0n1p2)"
    PART_ROOT="/dev/$PART_ROOT"
    [ -b "$PART_ROOT" ] || die "$PART_ROOT is not a block device"

    ask PART_EFI "efi partition (e.g. sda1, nvme0n1p1 — must already exist and be FAT32)"
    PART_EFI="/dev/$PART_EFI"
    [ -b "$PART_EFI" ] || die "$PART_EFI is not a block device"

    DISK=$(lsblk -no PKNAME "$PART_ROOT" | head -1)
    DISK="/dev/$DISK"

    echo ""
    warn "this will format $PART_ROOT. your other partitions will not be touched..."
    confirm "are you sure?" || die "aborted"

  elif [ "$PARTMODE" = "2" ]; then

    ask DISK "disk with unallocated space (e.g. sda, nvme0n1)"
    DISK="/dev/$DISK"
    [ -b "$DISK" ] || die "$DISK is not a block device"

    FREE_START=$(parted --script "$DISK" unit MiB print free 2>/dev/null \
      | awk '/Free Space/ { print $1 }' | tail -1)
    [ -n "$FREE_START" ] || die "no unallocated space found on $DISK"

    LAST_PART=$(parted --script "$DISK" print 2>/dev/null | awk '/^ [0-9]/ { print $1 }' | tail -1)
    NEXT_NUM=$(( LAST_PART + 1 ))

    if [[ "$DISK" == *"nvme"* ]]; then
      PART_EFI="${DISK}p${NEXT_NUM}"
      PART_ROOT="${DISK}p$(( NEXT_NUM + 1 ))"
    else
      PART_EFI="${DISK}${NEXT_NUM}"
      PART_ROOT="${DISK}$(( NEXT_NUM + 1 ))"
    fi

    AUTOPART=true

    warn "will create new partitions starting at ${FREE_START} on $DISK"
    confirm "are you sure?" || die "aborted"

  elif [ "$PARTMODE" = "3" ]; then

    ask DISK "disk to manage (e.g. sda, nvme0n1)"
    DISK="/dev/$DISK"
    [ -b "$DISK" ] || die "$DISK is not a block device"

    echo ""
    warn "cfdisk will open now. resize or create partitions as needed, then save and quit."
    warn "you will need at least: one FAT32 EFI partition (512M+) and one root partition (20G+)."
    warn "do NOT format them here — bloom will do that. just create/resize the partition entries."
    echo ""
    read -rp "$(echo -e "${c}  ?${w}  press enter to open cfdisk...")"
    cfdisk "$DISK"

    echo ""
    show_disks

    warn "enter the partitions bloom should use (created or freed up in cfdisk)"
    ask PART_ROOT "root partition (e.g. sda2, nvme0n1p2)"
    PART_ROOT="/dev/$PART_ROOT"
    [ -b "$PART_ROOT" ] || die "$PART_ROOT is not a block device"

    ask PART_EFI "efi partition (e.g. sda1, nvme0n1p1)"
    PART_EFI="/dev/$PART_EFI"
    [ -b "$PART_EFI" ] || die "$PART_EFI is not a block device"

    echo ""
    warn "this will format $PART_ROOT and $PART_EFI. other partitions will not be touched."
    confirm "are you sure?" || die "aborted"

  else
    die "invalid option"
  fi

fi

echo ""
say "encryption"
echo -e "  ${w}disk encryption keeps your data safe if the drive is lost or stolen.${w}"
echo -e "  ${w}you will enter a passphrase on every boot. make sure you remember it!!!!${w}"
echo ""
ask ENCRYPT "enable disk encryption?" "yes"

if [[ "$ENCRYPT" =~ ^[Yy] ]]; then
  USE_ENCRYPTION=true
else
  USE_ENCRYPTION=false
  warn "encryption disabled"
fi

echo ""
say "timezone"
echo -e "  ${y}hint:${w} America/New_York, America/Vancouver, Europe/London, Asia/Tokyo"
ask TIMEZONE "timezone" "America/Vancouver"

ask LOCALE "locale" "en_CA.UTF-8"
ask KEYMAP "keyboard layout" "us"

echo ""
say "system identity"
ask HOSTNAME "hostname" "bloom"
ask USERNAME "username"

echo ""
while true; do
  read -rsp "$(echo -e "${c}  ?${w}  password for $USERNAME: ")" UPASS; echo
  read -rsp "$(echo -e "${c}  ?${w}  confirm password: ")" UPASS2; echo
  [ "$UPASS" = "$UPASS2" ] && break
  warn "passwords don't match, try again!!"
done

if [ "$USE_ENCRYPTION" = true ]; then
  echo ""
  while true; do
    read -rsp "$(echo -e "${c}  ?${w}  luks passphrase: ")" LPASS; echo
    read -rsp "$(echo -e "${c}  ?${w}  confirm passphrase: ")" LPASS2; echo
    [ "$LPASS" = "$LPASS2" ] && break
    warn "passphrases don't match, try again!!"
  done
fi

echo ""
ask SWAPSIZE "swap size in GiB (0 to skip)" "4"

echo ""
say "display manager"
echo -e "  ${w}  1) sddm  (default)${w}"
echo -e "  ${w}  2) gdm${w}"
echo -e "  ${w}  3) custom${w}"
echo ""
ask DMMODE "greeter" "1"

if [ "$DMMODE" = "2" ]; then
  DM_PKG="gdm"
  DM_SVC="gdm"
elif [ "$DMMODE" = "3" ]; then
  ask DM_PKG "package name (e.g. ly, lightdm, lemurs)"
  if ! pacman -Si "$DM_PKG" &>/dev/null; then
    warn "$DM_PKG not found in repos — it may be AUR-only and will be installed via yay inside the chroot"
    DM_AUR=true
  fi
  ask DM_SVC "systemd service name to enable (e.g. ly, lightdm)"
else
  DM_PKG="sddm"
  DM_SVC="sddm"
fi

echo ""
say "install summary"
echo ""
echo "  disk       : $DISK"
if [ "$WIPE" = true ]; then
  echo "  mode       : wipe entire disk"
elif [ "$AUTOPART" = true ]; then
  echo "  mode       : use unallocated space (auto-partition)"
elif [ "${PARTMODE:-}" = "3" ]; then
  echo "  mode       : manual (cfdisk)"
else
  echo "  mode       : use existing partitions"
fi
echo "  efi        : $PART_EFI"
echo "  root       : $PART_ROOT"
echo "  encryption : $( [ "$USE_ENCRYPTION" = true ] && echo "yes (LUKS2)" || echo "no" )"
if [ "$SWAPSIZE" != "0" ]; then
  echo "  swap       : ${SWAPSIZE}G"
fi
echo "  timezone   : $TIMEZONE"
echo "  locale     : $LOCALE"
echo "  hostname   : $HOSTNAME"
echo "  user       : $USERNAME"
echo "  greeter    : $DM_PKG"
echo ""

confirm "looks good? this is the last chance to cancel! no going back after this." || die "aborted"

if [ "$WIPE" = true ]; then
  say "partitioning $DISK..."
  sgdisk -Z "$DISK"
  sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI" "$DISK"
  sgdisk -n 2:0:0     -t 2:8309 -c 2:"LUKS" "$DISK"
  partprobe "$DISK"
  sleep 2
  ok "partitioned"
fi

if [ "$AUTOPART" = true ]; then
  say "creating partitions in unallocated space on $DISK..."
  sgdisk -n "${NEXT_NUM}:0:+512M" -t "${NEXT_NUM}:ef00" -c "${NEXT_NUM}:EFI" "$DISK"
  sgdisk -n "$(( NEXT_NUM + 1 )):0:0" -t "$(( NEXT_NUM + 1 )):8309" -c "$(( NEXT_NUM + 1 )):LUKS" "$DISK"
  partprobe "$DISK"
  sleep 2
  ok "partitions created"
fi

if [ "$USE_ENCRYPTION" = true ]; then
  say "setting up LUKS on $PART_ROOT..."
  echo -n "$LPASS" | cryptsetup luksFormat \
    --type luks2 \
    --cipher aes-xts-plain64 \
    --key-size 512 \
    --hash sha512 \
    --iter-time 3000 \
    "$PART_ROOT" -
  echo -n "$LPASS" | cryptsetup open "$PART_ROOT" cryptroot -
  unset LPASS LPASS2
  ok "luks container opened as /dev/mapper/cryptroot"
  CRYPT_UUID=$(blkid -s UUID -o value "$PART_ROOT")
  LVM_TARGET="/dev/mapper/cryptroot"
else
  LVM_TARGET="$PART_ROOT"
fi

say "setting up LVM..."
pvcreate "$LVM_TARGET"
vgcreate bloom-vg "$LVM_TARGET"
if [ "$SWAPSIZE" != "0" ]; then
  lvcreate -L "${SWAPSIZE}G" bloom-vg -n swap
fi
lvcreate -l 100%FREE bloom-vg -n root
ok "LVM volumes created"

say "formatting..."
if [ "$WIPE" = true ] || [ "$AUTOPART" = true ] || [ "${PARTMODE:-}" = "3" ]; then
  mkfs.fat -F32 -n EFI "$PART_EFI"
fi
mkfs.ext4 -L bloom-root /dev/bloom-vg/root
if [ "$SWAPSIZE" != "0" ]; then
  mkswap -L bloom-swap /dev/bloom-vg/swap
fi
ok "filesystems created"

say "mounting..."
mount /dev/bloom-vg/root /mnt
mkdir -p /mnt/boot
mount "$PART_EFI" /mnt/boot
if [ "$SWAPSIZE" != "0" ]; then
  swapon /dev/bloom-vg/swap
fi
ok "mounted"

say "installing base system (grab a coffee, this takes a while!)..."
pacstrap /mnt \
  base base-devel linux linux-headers linux-firmware \
  intel-ucode tlp \
  lvm2 cryptsetup \
  networkmanager \
  sudo git curl wget \
  kitty firefox \
  fastfetch \
  fish \
  pipewire pipewire-alsa pipewire-pulse wireplumber \
  bluez bluez-utils \
  nano neovim vscodium \
  dosfstools e2fsprogs \
  ntfs-3g exfatprogs btrfs-progs \
  usbutils pciutils hdparm \
  iwd dhcpcd openssh iproute2 iputils bind \
  man-db man-pages less which tree unzip zip tar \
  noto-fonts noto-fonts-emoji ttf-jetbrains-mono \
  xdg-utils xdg-user-dirs polkit \
  parted \
  flatpak cmake ca-certificates \
  cmatrix asciiquarium cava \
  ffmpeg lm_sensors lua mesa \
  nodejs npm obsidian rsync tlp \
  $( [ "${DM_AUR:-false}" = false ] && echo "$DM_PKG" )
ok "base system installed"

genfstab -U /mnt >> /mnt/etc/fstab
ok "fstab generated"

say "configuring system..."

if [ "$USE_ENCRYPTION" = true ]; then
  MKINIT_HOOKS="HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt lvm2 filesystems fsck)"
  BOOT_OPTIONS="cryptdevice=UUID=$CRYPT_UUID:cryptroot:allow-discards root=/dev/bloom-vg/root rw quiet loglevel=3"
else
  MKINIT_HOOKS="HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block lvm2 filesystems fsck)"
  BOOT_OPTIONS="root=/dev/bloom-vg/root rw quiet loglevel=3"
fi

arch-chroot /mnt /bin/bash <<CHROOT
set -e

ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

echo "$LOCALE UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf

echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts <<HOSTS
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
HOSTS

sed -i "s/^HOOKS=.*/$MKINIT_HOOKS/" /etc/mkinitcpio.conf
mkinitcpio -P

useradd -m -G wheel,audio,video,storage,optical,network -s /bin/fish "$USERNAME"
echo "$USERNAME:$UPASS" | chpasswd

echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel

systemctl enable NetworkManager
systemctl enable bluetooth

cd /tmp
git clone https://aur.archlinux.org/yay.git
chown -R $USERNAME:$USERNAME yay
cd yay
sudo -u $USERNAME makepkg -si --noconfirm
cd /
rm -rf /tmp/yay

$( [ "${DM_AUR:-false}" = true ] && echo "sudo -u $USERNAME yay -S --noconfirm $DM_PKG" )

systemctl enable $DM_SVC

bootctl install

cat > /boot/loader/loader.conf <<LOADER
default bloom
timeout 3
console-mode max
editor no
LOADER

cat > /boot/loader/entries/bloom.conf <<ENTRY
title   bloom
linux   /vmlinuz-linux
initrd  /intel-ucode.img
initrd  /initramfs-linux.img
options $BOOT_OPTIONS
ENTRY

CHROOT

ok "chroot configuration done"

say "setting up fastfetch..."

FFCONF_DIR="/mnt/home/$USERNAME/.config/fastfetch"
mkdir -p "$FFCONF_DIR"

cat > "$FFCONF_DIR/bloom.txt" << 'BLOSSOM'
      _._
   .-( * )-.
  ( *  *  * )
   '-( * )-'
      `-'
BLOSSOM

cat > "$FFCONF_DIR/config.jsonc" << 'FFCFG'
{
  "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
  "logo": {
    "source": "~/.config/fastfetch/bloom.txt",
    "type": "file",
    "color": {
      "1": "magenta"
    }
  },
  "display": {
    "separator": "  "
  },
  "modules": [
    "break",
    { "type": "title", "format": "{user-name}@{host-name}" },
    "separator",
    { "type": "os",      "key": "os     " },
    { "type": "kernel",  "key": "kernel " },
    { "type": "wm",      "key": "wm     " },
    { "type": "shell",   "key": "shell  " },
    { "type": "terminal","key": "term   " },
    { "type": "cpu",     "key": "cpu    " },
    { "type": "memory",  "key": "ram    " },
    { "type": "uptime",  "key": "uptime " },
    "break",
    { "type": "colors", "paddingLeft": 2 },
    "break"
  ]
}
FFCFG

chown -R 1000:1000 "$FFCONF_DIR"
ok "fastfetch configured"

FISH_CONF_DIR="/mnt/home/$USERNAME/.config/fish"
mkdir -p "$FISH_CONF_DIR"

cat > "$FISH_CONF_DIR/config.fish" << 'FISHCFG'
if status is-login
    fastfetch
end
FISHCFG

chown -R 1000:1000 "$FISH_CONF_DIR"
ok "fish configured"

echo ""
say "installing fresh hyprland dotfiles..."
echo ""

arch-chroot /mnt sudo -u "$USERNAME" bash -c \
  'bash <(curl -s https://ii.clsty.link/get)'

ok "dotfiles installed"

say "installing lazyvim..."

arch-chroot /mnt sudo -u "$USERNAME" bash -c '
set -e

if [ ! -d ~/.config/nvim ]; then
  git clone https://github.com/LazyVim/starter ~/.config/nvim
  rm -rf ~/.config/nvim/.git
fi
'

ok "lazyvim installed"

say "bootstrapping lazyvim plugins (may take a little bit)..."

arch-chroot /mnt sudo -u "$USERNAME" bash -c '
set -e
nvim --headless "+Lazy sync" +qa
'

ok "lazyvim fully ready!!"

echo ""
echo -e "${m}"
cat << 'EOF'
      _._
   .-( * )-.
  ( *  *  * )
   '-( * )-'
      `-'

   bloom is installed.

EOF
echo -e "${w}"

say "unmounting..."
swapoff -a 2>/dev/null || true
umount -R /mnt
if [ "$USE_ENCRYPTION" = true ]; then
  cryptsetup close cryptroot
fi

echo ""
ok "bloom is now fully installed on your system! you can reboot now with the command 'reboot'."
echo ""
