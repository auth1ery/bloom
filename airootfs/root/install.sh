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

detect_ucode() {
  local vendor
  vendor=$(grep -m1 -oP '(?<=vendor_id\s: ).*' /proc/cpuinfo)
  case "$vendor" in
    GenuineIntel) echo "intel-ucode" ;;
    AuthenticAMD) echo "amd-ucode" ;;
    *)
      warn "unrecognized CPU vendor '$vendor', defaulting to no microcode package"
      echo ""
      ;;
  esac
}

clear
echo -e "${m}"
cat << 'EOF'
      _._
   .-( * )-.
  ( *  *  * )
   '-( * )-'
      `-'

        bloom
        a secure, beautiful, preconfigured arch-based 
        linux distro built around a hyprland workflow.

        by auth <3

EOF
echo -e "${w}"
echo -e "  ${y}defaults are shown in yellow! press enter to accept them${w}"
echo -e "  ${y}read each prompt carefully before continuing${w}"

timedatectl set-ntp true 2>/dev/null || true

say "disk setup"
show_disks

say "cpu detection"
UCODE_PKG=$(detect_ucode)
if [ -n "$UCODE_PKG" ]; then
  ok "detected CPU microcode package: $UCODE_PKG"
else
  warn "no microcode package will be installed"
fi

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
  warn "ALL data on $DISK will be permanently destroyed (and i mean it)"
  confirm "are you ABSOLUTELY sure?" || die "aborted"

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
  warn "do NOT format them in cfdisk! bloom will handle that by itself."
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
      warn "$DM_PKG not in official repos! will install via yay"
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
echo "  cpu ucode  : ${UCODE_PKG:-none}"
echo ""
confirm "looks good? no going back after this" || die "aborted"

echo ""
warn "the installer will run for a while unattended."
warn "some steps (yay, dotfiles) may prompt for your sudo password."
warn "if you miss a prompt and it times out, that step will be skipped."
warn "keep an eye on the screen during installation."
echo ""
read -rp "$(echo -e "${c}  ?${w}  press enter to begin...")"

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

say "refreshing mirrors..."
pacman -Sy --noconfirm reflector
reflector --latest 10 --sort rate --save /etc/pacman.d/mirrorlist
ok "mirrors refreshed"

say "installing base system (grab a coffee, this takes a while)..."
PACSTRAP_PKGS=(
  base base-devel linux linux-headers linux-firmware
  lvm2 cryptsetup
  networkmanager
  sudo git curl wget
  kitty
  fastfetch
  fish
  jq inotify-tools wl-clipboard wtype
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
  gst-libav gst-plugins-good gst-plugins-bad gst-plugins-ugly
  nodejs rsync tlp plymouth
  ufw fail2ban apparmor
  alsa-utils htop btop reflector
  sl figlet toilet fortune-mod cowsay tokei
  github-cli traceroute
)
[ -n "$UCODE_PKG" ] && PACSTRAP_PKGS+=("$UCODE_PKG")
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

sed -i 's/^#Color/Color/' /etc/pacman.conf
sed -i '/^Color/a ILoveCandy' /etc/pacman.conf
sed -i 's/^#ParallelDownloads = 5/ParallelDownloads = 10/' /etc/pacman.conf
sed -i 's/^#VerbosePkgLists/VerbosePkgLists/' /etc/pacman.conf

sed -i '/^#\[multilib\]/,+1 s/^#//' /etc/pacman.conf

sed -i "s/^HOOKS=.*/$MKINIT_HOOKS/" /etc/mkinitcpio.conf
mkinitcpio -P

useradd -m -G wheel,audio,video,storage,optical,network -s /bin/fish "$USERNAME"
echo "$USERNAME:$UPASS" | chpasswd
unset UPASS UPASS2
sudo -u "$USERNAME" xdg-user-dirs-update --force

echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel

systemctl enable NetworkManager
systemctl enable bluetooth
systemctl enable tlp
systemctl enable apparmor

cd /tmp
git clone https://aur.archlinux.org/yay.git || { echo "warn: failed to clone yay. AUR packages will not be installed"; exit 0; }
chown -R $USERNAME:$USERNAME yay
cd yay
sudo -u $USERNAME makepkg -si --noconfirm || { echo "warn: yay build failed. AUR packages will not be installed"; exit 0; }
cd /
rm -rf /tmp/yay

sudo -u $USERNAME yay -S --noconfirm \
  helium-browser-bin vscodium-bin obsidian-bin vesktop \
  obs-studio-git windsurf localsend ufw-docker android-studio \
  hollywood cbonsai tty-clock \
  $( [ "$DM_AUR" = true ] && echo "$DM_PKG" ) || warn "some AUR packages failed to install! you can install them manually after boot with yay"

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

{
  echo "title   bloom"
  echo "linux   /vmlinuz-linux"
  [ -n "$UCODE_PKG" ] && echo "initrd  /${UCODE_PKG}.img"
  echo "initrd  /initramfs-linux.img"
  echo "options $BOOT_OPTIONS"
} > /boot/loader/entries/bloom.conf

if [ ! -d /home/$USERNAME/.config/nvim ]; then
  sudo -u $USERNAME git clone https://github.com/LazyVim/starter /home/$USERNAME/.config/nvim 2>/dev/null \
    && rm -rf /home/$USERNAME/.config/nvim/.git \
    || echo "warn: lazyvim clone failed, skipping"
fi

sudo -u $USERNAME nvim --headless "+Lazy sync" +qa 2>/dev/null || true

flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true
flatpak install flathub -y com.spotify.Client || echo "warn: spotify install failed"
flatpak install flathub -y it.mijorus.gearlever || echo "warn: gearlever install failed"
flatpak install flathub -y io.github.eteran.edb-debugger || echo "warn: edb install failed"

cat > /etc/motd << 'MOTD'

      _._
   .-( * )-.
  ( *  *  * )
   '-( * )-'
      `-'

        bloom linux
        based on arch, built with love
        have fun ssh-ing!

MOTD

sed -i 's/^#PrintMotd no/PrintMotd yes/' /etc/ssh/sshd_config 2>/dev/null || true
grep -A1 "^Color" /etc/pacman.conf

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
    id: root
    width: 1920
    height: 1080
    color: "#1a0f22"

    property int sessionIndex: sessionModel.lastIndex
    property bool showLogin: false
    property real gridOffset: 0

    NumberAnimation on gridOffset {
        from: 0
        to: 40
        duration: 3000
        loops: Animation.Infinite
        running: true
    }

    Timer {
        id: clockTimer
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            timeText.text = Qt.formatTime(new Date(), "hh:mm")
            secondText.text = Qt.formatTime(new Date(), "ss")
            dateText.text = Qt.formatDate(new Date(), "dddd, MMMM d yyyy")
        }
    }

    Canvas {
        id: gridCanvas
        anchors.fill: parent
        opacity: 0.07

        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            ctx.strokeStyle = "#ffb6d9"
            ctx.lineWidth = 0.5
            var spacing = 40
            var ox = -(gridOffset % spacing)
            var oy = -(gridOffset % spacing)
            for (var x = ox; x < width + spacing; x += spacing) {
                ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, height); ctx.stroke()
            }
            for (var y = oy; y < height + spacing; y += spacing) {
                ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(width, y); ctx.stroke()
            }
        }

        Timer {
            interval: 16
            running: true
            repeat: true
            onTriggered: gridCanvas.requestPaint()
        }
    }

    Rectangle { width: 320; height: 320; radius: 160; color: "#2d0f3d"; opacity: 0.5
        anchors { top: parent.top; left: parent.left; topMargin: -80; leftMargin: -80 } }
    Rectangle { width: 240; height: 240; radius: 120; color: "#3d1a4a"; opacity: 0.4
        anchors { bottom: parent.bottom; right: parent.right; bottomMargin: -60; rightMargin: -60 } }
    Rectangle { width: 180; height: 180; radius: 90; color: "#ff80c0"; opacity: 0.06
        anchors { bottom: parent.bottom; left: parent.left; bottomMargin: 80; leftMargin: 60 } }

    Item {
        id: lockScreen
        anchors.fill: parent
        opacity: showLogin ? 0 : 1
        visible: opacity > 0

        Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.InOutQuad } }

        MouseArea {
            anchors.fill: parent
            onClicked: showLogin = true
        }

        Keys.onPressed: showLogin = true

        Column {
            anchors {
                left: parent.left
                leftMargin: parent.width * 0.1
                verticalCenter: parent.verticalCenter
            }
            spacing: 4

            Row {
                spacing: 12

                Text {
                    id: timeText
                    text: Qt.formatTime(new Date(), "hh:mm")
                    font.family: "JetBrains Mono"
                    font.pixelSize: 96
                    font.weight: Font.Light
                    color: "#ffb6d9"
                }

                Text {
                    id: secondText
                    text: Qt.formatTime(new Date(), "ss")
                    font.family: "JetBrains Mono"
                    font.pixelSize: 32
                    font.weight: Font.Light
                    color: "#a06080"
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 18
                }
            }

            Text {
                id: dateText
                text: Qt.formatDate(new Date(), "dddd, MMMM d yyyy")
                font.family: "JetBrains Mono"
                font.pixelSize: 18
                color: "#7a5570"
            }

            Item { height: 40; width: 1 }

            Row {
                spacing: 32

                Column {
                    spacing: 4
                    Text {
                        text: "hostname"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 11
                        color: "#5a3860"
                    }
                    Text {
                        text: userModel.lastUser + "@bloom"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 14
                        color: "#c084a8"
                    }
                }

                Column {
                    spacing: 4
                    Text {
                        text: "session"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 11
                        color: "#5a3860"
                    }
                    Text {
                        text: "hyprland"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 14
                        color: "#c084a8"
                    }
                }

                Column {
                    spacing: 4
                    Text {
                        text: "os"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 11
                        color: "#5a3860"
                    }
                    Text {
                        text: "bloom linux"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 14
                        color: "#c084a8"
                    }
                }
            }

            Item { height: 48; width: 1 }

            Row {
                spacing: 8
                Text {
                    text: "click anywhere to unlock"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 12
                    color: "#5a3860"
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 48
            spacing: 2

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "      _._"
                font.family: "JetBrains Mono"
                font.pixelSize: 11
                color: "#3d2040"
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "   .-( * )-."
                font.family: "JetBrains Mono"
                font.pixelSize: 11
                color: "#3d2040"
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "  ( *  *  * )"
                font.family: "JetBrains Mono"
                font.pixelSize: 11
                color: "#4a2850"
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "   '-( * )-'"
                font.family: "JetBrains Mono"
                font.pixelSize: 11
                color: "#3d2040"
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "      `-'"
                font.family: "JetBrains Mono"
                font.pixelSize: 11
                color: "#3d2040"
            }
        }
    }

    Item {
        id: loginScreen
        anchors.fill: parent
        opacity: showLogin ? 1 : 0
        visible: opacity > 0

        Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.InOutQuad } }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                if (!userField.contains(mapToItem(userField, mouse.x, mouse.y)) &&
                    !passField.contains(mapToItem(passField, mouse.x, mouse.y))) {
                    showLogin = false
                }
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: 16
            width: 340

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 2
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "      _._"; font.family: "JetBrains Mono"; font.pixelSize: 13; color: "#c084a8" }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "   .-( * )-."; font.family: "JetBrains Mono"; font.pixelSize: 13; color: "#d490b8" }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "  ( *  *  * )"; font.family: "JetBrains Mono"; font.pixelSize: 13; color: "#ffb6d9" }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "   '-( * )-'"; font.family: "JetBrains Mono"; font.pixelSize: 13; color: "#d490b8" }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "      \`-'"; font.family: "JetBrains Mono"; font.pixelSize: 13; color: "#c084a8" }
            }

            Item { height: 4; width: 1 }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "bloom"
                font.family: "JetBrains Mono"
                font.pixelSize: 42
                font.weight: Font.Light
                color: "#ffb6d9"
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDate(new Date(), "dddd, MMMM d")
                font.family: "JetBrains Mono"
                font.pixelSize: 12
                color: "#7a5570"
            }

            Item { height: 8; width: 1 }

            Rectangle {
                width: parent.width
                height: 56
                radius: 28
                color: userField.activeFocus ? "#2e1840" : "#22112e"
                border.color: userField.activeFocus ? "#ffb6d9" : "#4a2860"
                border.width: userField.activeFocus ? 2 : 1
                Behavior on border.color { ColorAnimation { duration: 200 } }
                Behavior on color { ColorAnimation { duration: 200 } }

                Text {
                    anchors.left: parent.left; anchors.leftMargin: 24
                    anchors.verticalCenter: parent.verticalCenter
                    text: "username"; font.family: "JetBrains Mono"; font.pixelSize: 13
                    color: "#5a3860"; visible: userField.text.length === 0
                }
                TextInput {
                    id: userField
                    anchors.fill: parent; anchors.leftMargin: 24; anchors.rightMargin: 24
                    text: userModel.lastUser
                    font.family: "JetBrains Mono"; font.pixelSize: 13; color: "#ffb6d9"
                    verticalAlignment: TextInput.AlignVCenter
                    KeyNavigation.tab: passField
                }
            }

            Rectangle {
                width: parent.width
                height: 56
                radius: 28
                color: passField.activeFocus ? "#2e1840" : "#22112e"
                border.color: passField.activeFocus ? "#ffb6d9" : "#4a2860"
                border.width: passField.activeFocus ? 2 : 1
                Behavior on border.color { ColorAnimation { duration: 200 } }
                Behavior on color { ColorAnimation { duration: 200 } }

                Text {
                    anchors.left: parent.left; anchors.leftMargin: 24
                    anchors.verticalCenter: parent.verticalCenter
                    text: "password"; font.family: "JetBrains Mono"; font.pixelSize: 13
                    color: "#5a3860"; visible: passField.text.length === 0
                }
                TextInput {
                    id: passField
                    anchors.fill: parent; anchors.leftMargin: 24; anchors.rightMargin: 24
                    echoMode: TextInput.Password
                    font.family: "JetBrains Mono"; font.pixelSize: 13; color: "#ffb6d9"
                    verticalAlignment: TextInput.AlignVCenter
                    Keys.onReturnPressed: sddm.login(userField.text, passField.text, sessionIndex)
                }
            }

            Rectangle {
                width: parent.width
                height: 56
                radius: 28
                color: loginBtn.containsMouse ? "#ff80c0" : "#ffb6d9"
                Behavior on color { ColorAnimation { duration: 150 } }

                Text {
                    anchors.centerIn: parent
                    text: "sign in"; color: "#1a0f22"
                    font.family: "JetBrains Mono"; font.pixelSize: 14; font.weight: Font.Medium
                }
                MouseArea {
                    id: loginBtn
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
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

lines = ["      _._", "   .-( * )-.", "  ( *  *  * )", "   '-( * )-'", "      `-'"];
colors_r = [0.75, 0.83, 1.0, 0.83, 0.75];
colors_g = [0.52, 0.56, 0.71, 0.56, 0.52];
colors_b = [0.66, 0.72, 0.85, 0.72, 0.66];

num_lines = 5;
sprites = [];
line_height = 20;
total_height = num_lines * line_height;
start_y = screen_height / 2 - total_height / 2 - 30;

for (i = 0; i < num_lines; i++) {
    img = Image.Text(lines[i], colors_r[i], colors_g[i], colors_b[i], 1);
    s = Sprite(img);
    s.SetX(screen_width / 2 - img.GetWidth() / 2);
    s.SetY(start_y + i * line_height);
    s.SetOpacity(0);
    sprites[i] = s;
}

label = Image.Text("bloom", 1.0, 0.71, 0.85, 1);
label_sprite = Sprite(label);
label_sprite.SetX(screen_width / 2 - label.GetWidth() / 2);
label_sprite.SetY(start_y + num_lines * line_height + 16);
label_sprite.SetOpacity(0);

dots_count = 3;
dot_sprites = [];
dot_x_start = screen_width / 2 - 20;
dots_y = start_y + num_lines * line_height + 52;

for (i = 0; i < dots_count; i++) {
    dot = Image.Text("·", 1.0, 0.71, 0.85, 1);
    s = Sprite(dot);
    s.SetX(dot_x_start + i * 20);
    s.SetY(dots_y);
    s.SetOpacity(0);
    dot_sprites[i] = s;
}

counter = 0;
reveal_delay = 30;

fun refresh_callback() {
    counter++;

    for (i = 0; i < num_lines; i++) {
        trigger = i * reveal_delay;
        if (counter > trigger) {
            elapsed = counter - trigger;
            fade_frames = 20;
            if (elapsed < fade_frames) {
                sprites[i].SetOpacity(elapsed / fade_frames);
            } else {
                sprites[i].SetOpacity(1);
            }
        }
    }

    label_trigger = num_lines * reveal_delay + 10;
    if (counter > label_trigger) {
        elapsed = counter - label_trigger;
        fade_frames = 25;
        if (elapsed < fade_frames) {
            label_sprite.SetOpacity(elapsed / fade_frames);
        } else {
            label_sprite.SetOpacity(1);
        }
    }

    dots_trigger = label_trigger + 30;
    if (counter > dots_trigger) {
        for (i = 0; i < dots_count; i++) {
            phase = Math.Sin((counter / 30.0 + i * 0.5) * 3.14159);
            op = (phase + 1) / 2;
            dot_sprites[i].SetOpacity(op);
        }
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

sed -i 's/rw quiet loglevel=3/rw quiet loglevel=3 splash/' /mnt/boot/loader/entries/bloom.conf

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

alias cls clear
alias h history
alias q exit
FISHCFG
chown -R 1000:1000 "$FISH_CONF_DIR"
ok "fish configured"

say "installing custom CLI tools..."

TOOLS_SRC="$(dirname "$(readlink -f "$0")")/bloom-bin"
mkdir -p /mnt/usr/local/bin

for tool in secure repaste; do
  src="$TOOLS_SRC/$tool"
  if [ -f "$src" ]; then
    cp "$src" /mnt/usr/local/bin/"$tool"
    chmod 755 /mnt/usr/local/bin/"$tool"
    ok "installed $tool -> /usr/local/bin/$tool"
  else
    warn "$tool not found at $src, skipping"
  fi
done

say "installing hyprland dotfiles..."
if arch-chroot /mnt sudo -u "$USERNAME" bash -c 'bash <(curl -s https://ii.clsty.link/get)'; then
  ok "dotfiles installed"
else
  warn "dotfiles install failed or was interrupted!!! run 'bash <(curl -s https://ii.clsty.link/get)' manually after boot if you want the hyprland dotfiles..."
fi

echo ""
echo -e "${m}"
cat << 'EOF'
      _._
   .-( * )-.
  ( *  *  * )
   '-( * )-'
      `-'

   bloom is installed.

   enjoy your new system that
   you actually own!

EOF
echo -e "${w}"

say "unmounting..."
swapoff -a 2>/dev/null || true
umount -R /mnt
[ "$USE_ENCRYPTION" = true ] && cryptsetup close cryptroot

echo ""
ok "all done! reboot with 'reboot'."
echo ""
