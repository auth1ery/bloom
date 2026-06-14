#!/bin/bash

set -e

r="\e[31m" g="\e[32m" y="\e[33m" b="\e[34m" m="\e[38;2;255;182;217m" c="\e[36m" w="\e[0m"

say()  { echo -e "\n${b}bloom${w} :: $*"; }
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
  echo -e "  ${c}disks:${w}"
  echo ""
  lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT | grep -v loop
  echo ""
  echo -e "  ${c}free space:${w}"
  local found=false
  for d in $(lsblk -dno NAME | grep -v loop); do
    while IFS= read -r line; do
      found=true
      echo "  /dev/$d: $line"
    done < <(parted --script /dev/$d unit GiB print free 2>/dev/null \
      | awk '/Free Space/ { printf "%s free (%s–%s)\n", $3, $1, $2 }')
  done
  if [ "$found" = false ]; then
    echo -e "  ${y}  none detected${w}"
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

        bloom — arch linux installer
        by auth

EOF
echo -e "${w}"
echo -e "  ${y}defaults are shown in yellow — press enter to accept them${w}"
echo -e "  ${y}read each prompt carefully before continuing${w}"

timedatectl set-ntp true 2>/dev/null || true

say "disk setup"
show_disks

WIPE=false
AUTOPART=false
FORMAT_EFI=false

echo -e "  ${w}how do you want to partition?${w}"
echo -e "  ${w}  1) wipe an entire disk  (default)${w}"
echo -e "  ${w}  2) use existing partitions${w}"
echo -e "  ${w}  3) use unallocated space (auto-partition)${w}"
echo -e "  ${w}  4) manually partition with cfdisk${w}"
echo ""
ask PARTMODE "partition mode" "1"

if [ "$PARTMODE" = "1" ]; then

  ask DISK "disk to wipe (e.g. sda, nvme0n1)"
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
  FORMAT_EFI=true
  echo ""
  warn "ALL data on $DISK will be permanently destroyed"
  confirm "are you absolutely sure?" || die "aborted"

elif [ "$PARTMODE" = "2" ]; then

  warn "the root partition will be formatted. other partitions will not be touched."
  warn "efi partition must already exist and be FAT32. it will NOT be reformatted."
  echo ""
  ask PART_ROOT "root partition (e.g. sda3, nvme0n1p3)"
  PART_ROOT="/dev/$PART_ROOT"
  [ -b "$PART_ROOT" ] || die "$PART_ROOT is not a block device"
  ask PART_EFI "existing efi partition (e.g. sda1, nvme0n1p1)"
  PART_EFI="/dev/$PART_EFI"
  [ -b "$PART_EFI" ] || die "$PART_EFI is not a block device"
  DISK=$(lsblk -no PKNAME "$PART_ROOT" | head -1)
  DISK="/dev/$DISK"
  echo ""
  warn "$PART_ROOT will be wiped and formatted as ext4"
  confirm "are you sure?" || die "aborted"

elif [ "$PARTMODE" = "3" ]; then

  ask DISK "disk with unallocated space (e.g. sda, nvme0n1)"
  DISK="/dev/$DISK"
  [ -b "$DISK" ] || die "$DISK is not a block device"
  FREE_START=$(parted --script "$DISK" unit MiB print free 2>/dev/null \
    | awk '/Free Space/ { print $1 }' | tail -1)
  [ -n "$FREE_START" ] || die "no unallocated space found on $DISK"
  LAST_PART=$(parted --script "$DISK" print 2>/dev/null | awk '/^ [0-9]/ { print $1 }' | tail -1)
  NEXT_NUM=$(( ${LAST_PART:-0} + 1 ))
  if [[ "$DISK" == *"nvme"* ]]; then
    PART_EFI="${DISK}p${NEXT_NUM}"
    PART_ROOT="${DISK}p$(( NEXT_NUM + 1 ))"
  else
    PART_EFI="${DISK}${NEXT_NUM}"
    PART_ROOT="${DISK}$(( NEXT_NUM + 1 ))"
  fi
  AUTOPART=true
  FORMAT_EFI=true
  echo ""
  warn "new partitions will be created in unallocated space starting at $FREE_START on $DISK"
  confirm "are you sure?" || die "aborted"

elif [ "$PARTMODE" = "4" ]; then

  ask DISK "disk to manage (e.g. sda, nvme0n1)"
  DISK="/dev/$DISK"
  [ -b "$DISK" ] || die "$DISK is not a block device"
  echo ""
  warn "cfdisk will open now. create or resize partitions, then save and quit."
  warn "you need: a FAT32 EFI partition (512M+) and a root partition (20G+)."
  warn "do NOT format them in cfdisk — bloom will handle that."
  echo ""
  read -rp "$(echo -e "${c}  ?${w}  press enter to open cfdisk...")"
  cfdisk "$DISK"
  show_disks
  warn "enter the partitions bloom should use"
  ask PART_ROOT "root partition (e.g. sda2, nvme0n1p2)"
  PART_ROOT="/dev/$PART_ROOT"
  [ -b "$PART_ROOT" ] || die "$PART_ROOT is not a block device"
  ask PART_EFI "efi partition (e.g. sda1, nvme0n1p1)"
  PART_EFI="/dev/$PART_EFI"
  [ -b "$PART_EFI" ] || die "$PART_EFI is not a block device"
  FORMAT_EFI=true
  echo ""
  warn "$PART_ROOT and $PART_EFI will be formatted. other partitions are untouched."
  confirm "are you sure?" || die "aborted"

else
  die "invalid option"
fi

say "encryption"
echo -e "  ${w}encrypts your disk with LUKS2. you will enter a passphrase on every boot.${w}"
echo -e "  ${w}strongly recommended on laptops and portable drives.${w}"
echo ""
ask ENCRYPT "enable disk encryption?" "yes"
if [[ "$ENCRYPT" =~ ^[Yy] ]]; then
  USE_ENCRYPTION=true
else
  USE_ENCRYPTION=false
  warn "encryption disabled"
fi

say "locale & timezone"
echo -e "  ${y}hint:${w} America/New_York  America/Vancouver  Europe/London  Asia/Tokyo"
ask TIMEZONE "timezone" "America/Vancouver"
ask LOCALE "locale" "en_CA.UTF-8"
ask KEYMAP "keyboard layout" "us"

say "system identity"
ask HOSTNAME "hostname" "bloom"
ask USERNAME "username"

echo ""
while true; do
  read -rsp "$(echo -e "${c}  ?${w}  password for $USERNAME: ")" UPASS; echo
  read -rsp "$(echo -e "${c}  ?${w}  confirm password: ")" UPASS2; echo
  [ "$UPASS" = "$UPASS2" ] && break
  warn "passwords don't match, try again"
done

if [ "$USE_ENCRYPTION" = true ]; then
  echo ""
  while true; do
    read -rsp "$(echo -e "${c}  ?${w}  luks passphrase: ")" LPASS; echo
    read -rsp "$(echo -e "${c}  ?${w}  confirm passphrase: ")" LPASS2; echo
    [ "$LPASS" = "$LPASS2" ] && break
    warn "passphrases don't match, try again"
  done
fi

say "swap"
ask SWAPSIZE "swap size in GiB (0 to skip)" "4"

say "display manager"
echo -e "  ${w}  1) sddm  (default)${w}"
echo -e "  ${w}  2) gdm${w}"
echo -e "  ${w}  3) ly${w}"
echo -e "  ${w}  4) custom${w}"
echo ""
ask DMMODE "greeter" "1"

case "$DMMODE" in
  2) DM_PKG="gdm";    DM_SVC="gdm";    DM_AUR=false ;;
  3) DM_PKG="ly";     DM_SVC="ly";     DM_AUR=true  ;;
  4)
    ask DM_PKG "package name"
    ask DM_SVC "systemd service name"
    if pacman -Si "$DM_PKG" &>/dev/null; then
      DM_AUR=false
    else
      warn "$DM_PKG not in official repos — will install via yay"
      DM_AUR=true
    fi
    ;;
  *) DM_PKG="sddm";   DM_SVC="sddm";   DM_AUR=false ;;
esac

say "install summary"
echo ""
echo "  disk       : $DISK"
case "$PARTMODE" in
  1) echo "  mode       : wipe entire disk" ;;
  2) echo "  mode       : use existing partitions" ;;
  3) echo "  mode       : auto-partition unallocated space" ;;
  4) echo "  mode       : manual (cfdisk)" ;;
esac
echo "  efi        : $PART_EFI$( [ "$FORMAT_EFI" = true ] && echo " (will format)" || echo " (existing, kept)" )"
echo "  root       : $PART_ROOT (will format)"
echo "  encryption : $( [ "$USE_ENCRYPTION" = true ] && echo "yes (LUKS2)" || echo "no" )"
[ "$SWAPSIZE" != "0" ] && echo "  swap       : ${SWAPSIZE}G (inside LVM)"
echo "  timezone   : $TIMEZONE"
echo "  locale     : $LOCALE"
echo "  hostname   : $HOSTNAME"
echo "  user       : $USERNAME"
echo "  greeter    : $DM_PKG"
echo ""
confirm "looks good? no going back after this" || die "aborted"

say "checking internet connection..."
until ping -c 1 -W 3 archlinux.org &>/dev/null; do
  warn "no internet detected. make sure you're connected and press enter to retry, or Ctrl+C to abort."
  read -rp ""
done
ok "internet ok"

if [ "$WIPE" = true ]; then
  say "partitioning $DISK..."
  sgdisk -Z "$DISK"
  sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI"  "$DISK"
  sgdisk -n 2:0:0     -t 2:8309 -c 2:"LUKS" "$DISK"
  partprobe "$DISK"
  sleep 2
  ok "partitioned"
fi

if [ "$AUTOPART" = true ]; then
  say "creating partitions in unallocated space on $DISK..."
  sgdisk -n "${NEXT_NUM}:0:+512M"        -t "${NEXT_NUM}:ef00"  -c "${NEXT_NUM}:EFI"  "$DISK"
  sgdisk -n "$(( NEXT_NUM+1 )):0:0"      -t "$(( NEXT_NUM+1 )):8309" -c "$(( NEXT_NUM+1 )):LUKS" "$DISK"
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
[ "$SWAPSIZE" != "0" ] && lvcreate -L "${SWAPSIZE}G" bloom-vg -n swap
lvcreate -l 100%FREE bloom-vg -n root
ok "LVM volumes created"

say "formatting..."
[ "$FORMAT_EFI" = true ] && mkfs.fat -F32 -n EFI "$PART_EFI"
mkfs.ext4 -L bloom-root /dev/bloom-vg/root
[ "$SWAPSIZE" != "0" ] && mkswap -L bloom-swap /dev/bloom-vg/swap
ok "filesystems created"

say "mounting..."
mount /dev/bloom-vg/root /mnt
mkdir -p /mnt/boot
mount "$PART_EFI" /mnt/boot
[ "$SWAPSIZE" != "0" ] && swapon /dev/bloom-vg/swap
ok "mounted"

say "installing base system (grab a coffee, this takes a while)..."
PACSTRAP_PKGS=(
  base base-devel linux linux-headers linux-firmware
  intel-ucode
  lvm2 cryptsetup
  networkmanager
  sudo git curl wget
  kitty
  fastfetch
  fish
  pipewire pipewire-alsa pipewire-pulse wireplumber
  bluez bluez-utils
  nano neovim
  dosfstools e2fsprogs
  ntfs-3g exfatprogs btrfs-progs
  usbutils pciutils hdparm
  iwd dhcpcd openssh iproute2 iputils bind
  man-db man-pages less which tree unzip zip tar
  noto-fonts noto-fonts-emoji ttf-jetbrains-mono
  xdg-utils xdg-user-dirs polkit
  parted
  flatpak cmake ca-certificates
  cmatrix cava
  ffmpeg lm_sensors lua mesa
  nodejs rsync tlp plymouth \
  ufw fail2ban apparmor
)
[ "$DM_AUR" = false ] && PACSTRAP_PKGS+=("$DM_PKG")
pacstrap /mnt "${PACSTRAP_PKGS[@]}"
ok "base system installed"

genfstab -U /mnt >> /mnt/etc/fstab
ok "fstab generated"

say "configuring system..."

if [ "$USE_ENCRYPTION" = true ]; then
  MKINIT_HOOKS="HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt lvm2 filesystems fsck)"
  BOOT_OPTIONS="cryptdevice=UUID=$CRYPT_UUID:cryptroot:allow-discards root=/dev/bloom-vg/root rw quiet loglevel=3 lsm=landlock,lockdown,yama,integrity,apparmor,bpf"
else
  MKINIT_HOOKS="HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block lvm2 filesystems fsck)"
  BOOT_OPTIONS="root=/dev/bloom-vg/root rw quiet loglevel=3 lsm=landlock,lockdown,yama,integrity,apparmor,bpf"
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

sed -i 's/^NAME=.*/NAME="Bloom Linux"/' /etc/os-release
sed -i 's/^PRETTY_NAME=.*/PRETTY_NAME="Bloom Linux"/' /etc/os-release

sed -i "s/^HOOKS=.*/$MKINIT_HOOKS/" /etc/mkinitcpio.conf
mkinitcpio -P

useradd -m -G wheel,audio,video,storage,optical,network -s /bin/fish "$USERNAME"
echo "$USERNAME:$UPASS" | chpasswd
unset UPASS UPASS2

echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel

systemctl enable NetworkManager
systemctl enable bluetooth
systemctl enable tlp
systemctl enable apparmor

cd /tmp
git clone https://aur.archlinux.org/yay.git
chown -R $USERNAME:$USERNAME yay
cd yay
sudo -u $USERNAME makepkg -si --noconfirm
cd /
rm -rf /tmp/yay

sudo -u $USERNAME yay -S --noconfirm \
  helium-browser-bin vscodium-bin obsidian-bin vesktop \
  obs-studio-git windsurf localsend ufw-docker \
  $( [ "$DM_AUR" = true ] && echo "$DM_PKG" )

systemctl enable $DM_SVC

ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 53317/tcp
ufw allow 53317/udp
ufw enable
systemctl enable ufw

cat > /etc/ufw/applications.d/localsend << 'EOF'
[LocalSend]
title=LocalSend
description=Open source cross-platform alternative to AirDrop
ports=53317/tcp|53317/udp
EOF

systemctl enable fail2ban

cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
port = ssh
EOF

cat > /etc/sysctl.d/99-bloom-hardening.conf << 'EOF'
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.log_martians = 1
EOF

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

if [ ! -d /home/$USERNAME/.config/nvim ]; then
  sudo -u $USERNAME git clone https://github.com/LazyVim/starter /home/$USERNAME/.config/nvim
  rm -rf /home/$USERNAME/.config/nvim/.git
fi

sudo -u $USERNAME nvim --headless "+Lazy sync" +qa 2>/dev/null || true

flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install flathub -y \
  com.spotify.Client \
  it.mijorus.gearlever \
  io.github.eteran.edb-debugger

CHROOT

ok "chroot configuration done"

say "setting up branding..."

echo "Bloom Linux" > /mnt/etc/issue

cat > /mnt/etc/bloom-release << 'BLOOMREL'
NAME="Bloom Linux"
VERSION="1.0"
BASED_ON="Arch Linux"
MAINTAINER="auth"
BLOOMREL

say "setting up SDDM theme..."

mkdir -p /mnt/usr/share/sddm/themes/bloom

cat > /mnt/usr/share/sddm/themes/bloom/metadata.desktop << 'META'
[SddmGreeterTheme]
Name=bloom
Description=bloom linux login
Author=auth
META

cat > /mnt/usr/share/sddm/themes/bloom/Main.qml << 'QML'
import QtQuick 2.15
import QtQuick.Controls 2.15
import SddmComponents 2.0

Rectangle {
    width: Screen.width
    height: Screen.height
    color: "#1a1a2e"

    property int sessionIndex: sessionModel.lastIndex

    Rectangle {
        anchors.centerIn: parent
        width: 340
        height: 420
        radius: 16
        color: "#2a1f2e"

        Column {
            anchors.centerIn: parent
            spacing: 16

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "bloom"
                font.pixelSize: 32
                font.family: "JetBrains Mono"
                color: "#ffb6d9"
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "      _._\n   .-( * )-.\n  ( *  *  * )\n   '-( * )-'\n      \`-'"
                font.pixelSize: 11
                font.family: "JetBrains Mono"
                color: "#cc88aa"
                lineHeight: 1.3
            }

            Item { height: 8; width: 1 }

            Rectangle {
                width: 260
                height: 38
                radius: 8
                color: "#3d2a3d"
                border.color: "#ffb6d9"
                border.width: 1

                TextInput {
                    id: userField
                    anchors.fill: parent
                    anchors.margins: 10
                    text: userModel.lastUser
                    font.family: "JetBrains Mono"
                    font.pixelSize: 13
                    color: "#ffb6d9"
                    verticalAlignment: TextInput.AlignVCenter

                    Text {
                        anchors.fill: parent
                        text: "username"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 13
                        color: "#885566"
                        verticalAlignment: Text.AlignVCenter
                        visible: userField.text.length === 0
                    }
                }
            }

            Rectangle {
                width: 260
                height: 38
                radius: 8
                color: "#3d2a3d"
                border.color: "#ffb6d9"
                border.width: 1

                TextInput {
                    id: passField
                    anchors.fill: parent
                    anchors.margins: 10
                    echoMode: TextInput.Password
                    font.family: "JetBrains Mono"
                    font.pixelSize: 13
                    color: "#ffb6d9"
                    verticalAlignment: TextInput.AlignVCenter
                    Keys.onReturnPressed: sddm.login(userField.text, passField.text, sessionIndex)

                    Text {
                        anchors.fill: parent
                        text: "password"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 13
                        color: "#885566"
                        verticalAlignment: Text.AlignVCenter
                        visible: passField.text.length === 0
                    }
                }
            }

            Rectangle {
                width: 260
                height: 38
                radius: 8
                color: "#ffb6d9"

                Text {
                    anchors.centerIn: parent
                    text: "login"
                    color: "#1a1a2e"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 13
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: sddm.login(userField.text, passField.text, sessionIndex)
                }
            }
        }
    }
}
QML

cat > /mnt/etc/sddm.conf << 'SDDMCONF'
[Theme]
Current=bloom
SDDMCONF

ok "SDDM theme configured"

say "setting up plymouth..."

mkdir -p /mnt/usr/share/plymouth/themes/bloom

cat > /mnt/usr/share/plymouth/themes/bloom/bloom.plymouth << 'PLYMOUTH'
[Plymouth Theme]
Name=bloom
Description=bloom linux boot splash
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/bloom
ScriptFile=/usr/share/plymouth/themes/bloom/bloom.script
PLYMOUTH

cat > /mnt/usr/share/plymouth/themes/bloom/bloom.script << 'PLYSCRIPT'
screen_width = Window.GetWidth();
screen_height = Window.GetHeight();

background = Rectangle();
background.SetColor(0.1, 0.07, 0.12, 1);
background.SetX(0);
background.SetY(0);
background.SetWidth(screen_width);
background.SetHeight(screen_height);

logo = Image.Text("bloom", 1.0, 0.71, 0.85, 1);
logo_sprite = Sprite(logo);
logo_sprite.SetX(screen_width / 2 - logo.GetWidth() / 2);
logo_sprite.SetY(screen_height / 2 - 40);

dots_count = 3;
dot_sprites = [];
dot_x_start = screen_width / 2 - 20;

for (i = 0; i < dots_count; i++) {
    dot = Image.Text("·", 1.0, 0.71, 0.85, 1);
    s = Sprite(dot);
    s.SetX(dot_x_start + i * 20);
    s.SetY(screen_height / 2 + 10);
    s.SetOpacity(0);
    dot_sprites[i] = s;
}

counter = 0;

fun refresh_callback() {
    counter++;
    for (i = 0; i < dots_count; i++) {
        phase = Math.Sin((counter / 30.0 + i * 0.5) * 3.14159);
        op = (phase + 1) / 2;
        dot_sprites[i].SetOpacity(op);
    }
}

Plymouth.SetRefreshFunction(refresh_callback);
PLYSCRIPT

arch-chroot /mnt /bin/bash << 'PLYCHROOT'
cat > /etc/plymouth/plymouthd.conf << 'PLYCONF'
[Daemon]
Theme=bloom
ShowDelay=0
PLYCONF
sed -i 's/^HOOKS=(base /HOOKS=(base plymouth /' /etc/mkinitcpio.conf
echo "MODULES=(i915)" >> /etc/mkinitcpio.conf
sed -i 's/^MODULES=()$//' /etc/mkinitcpio.conf
mkinitcpio -P
PLYCHROOT

sed -i 's/ quiet loglevel=3$/ quiet loglevel=3 splash/' /mnt/boot/loader/entries/bloom.conf

ok "plymouth configured"

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
    "color": { "1": "magenta" }
  },
  "display": { "separator": "  " },
  "modules": [
    "break",
    { "type": "title",   "format": "{user-name}@{host-name}" },
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

say "setting up fish..."
FISH_CONF_DIR="/mnt/home/$USERNAME/.config/fish"
mkdir -p "$FISH_CONF_DIR"
cat > "$FISH_CONF_DIR/config.fish" << 'FISHCFG'
if status is-login
    set -gx XDG_DATA_DIRS /var/lib/flatpak/exports/share $HOME/.local/share/flatpak/exports/share $XDG_DATA_DIRS
    fastfetch
end
FISHCFG
chown -R 1000:1000 "$FISH_CONF_DIR"
ok "fish configured"

say "installing hyprland dotfiles..."
arch-chroot /mnt sudo -u "$USERNAME" bash -c \
  'bash <(curl -s https://ii.clsty.link/get)'
ok "dotfiles installed"

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
[ "$USE_ENCRYPTION" = true ] && cryptsetup close cryptroot

echo ""
ok "all done. reboot with 'reboot'."
echo ""
