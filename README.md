# bloom
a secure, beautiful, pre-configured arch-based linux distro built around a hyprland workflow. made by auth, for auth: but feel free to build it yourself.
bloom comes with disk encryption (LUKS2), a custom installer, developer tools, and a curated set of apps out of the box. it is not designed for beginners. it requires some familiarity with arch linux and the command line! this is still arch under the hood, so you maintain your own system still.

> **note:** bloom currently installs intel-ucode and assumes an intel CPU. AMD support is not handled by the installer yet!!

## what's included
- hyprland (via dotfiles installer at ii.clsty.link)
- kitty, fish, fastfetch
- neovim + lazyvim
- vesktop, helium browser, vscodium, obsidian, windsurf
- obs-studio, localsend
- spotify, gear lever, edb debugger (flatpak)
- pipewire, bluez, networkmanager, tlp
- disk encryption with LUKS2 + LVM (optional but recommended)
- optional swap inside LVM
- systemd-boot bootloader
- custom SDDM login theme
- custom plymouth boot splash
- yay (AUR helper)

## security
bloom ships with a hardened default configuration to be used for real-work-in-the-real-world.

- optional full-disk encryption via LUKS2
- UFW firewall (default deny incoming, outgoing allowed; SSH and LocalSend ports open)
- fail2ban with SSH protection enabled
- apparmor (enabled at boot via kernel parameters)
- kernel hardening via sysctl (pointer restrictions, ICMP protection, TCP syncookies, martian logging, and more)

## installer
the installer (`install.sh`) walks you through everything interactively. it supports four partitioning modes:
1. **wipe an entire disk** > formats and partitions from scratch
2. **use existing partitions** > bring your own EFI and root partitions
3. **use unallocated space** > carves new partitions out of free space on an existing disk
4. **manual (cfdisk)** > opens cfdisk for custom layouts, then asks which partitions to use

all modes set up LVM on top of the root partition (inside LUKS if encryption is enabled).

## dotfiles

the included hyprland dotfile (illogical-impulse) is not made or maintained by this project at all! please show support:

https://github.com/end-4/dots-hyprland

## building
bloom does not give an iso by default for you to install and check signatures. fortunately, the building process is not too complex at all, but it does require the command line!

you must be on arch linux with `archiso` installed:
```
sudo pacman -S archiso
```
clone the repo:
```
git clone https://github.com/auth1ery/bloom.git
cd bloom
```
build:
```
sudo mkarchiso -v -w /tmp/bloom-work -o /tmp/bloom-out ~/bloom
```
to rebuild from scratch:
```
sudo rm -rf /tmp/bloom-work /tmp/bloom-out
sudo mkarchiso -v -w /tmp/bloom-work -o /tmp/bloom-out ~/bloom
```
building takes a few minutes. the output ISO will be in `/tmp/bloom-out/`.

## installing
flash the ISO to a USB drive:
```
dd if=/tmp/bloom-out/bloom-*.iso of=/dev/sdX bs=4M status=progress
```
boot from the USB, then type `install` at the shell prompt to start the installer. the installer will walk you through partitioning, encryption, locale, user setup, and everything else!

## more info

https://bloom.cloudlull.fyi

(released under the MIT license)
