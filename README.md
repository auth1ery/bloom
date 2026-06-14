# bloom

a pre-configured arch-based linux distro built around a hyprland workflow. made by auth, for auth: but feel free to build it yourself.

bloom comes with disk encryption (LUKS2), a custom installer, developer tools, and a curated set of apps out of the box. it is not designed for beginners. it requires some familiarity with arch linux and the command line! this is still arch under the hood, so you maintain your own system still.

## what's included

- hyprland (via illogical-impulse dotfiles by end-4)
- kitty, fish, fastfetch
- neovim + lazyvim
- vesktop, helium browser, vscodium, obsidian
- spotify, gear lever, edb debugger (flatpak)
- pipewire, bluez, networkmanager
- disk encryption with LUKS2 + LVM
- custom SDDM login theme
- custom plymouth boot splash
- yay (AUR helper)

## dotfiles

the included hyprland config is not made or maintained by this project. it is based on the open-source illogical-impulse project by end-4:

https://github.com/end-4/dots-hyprland

## building

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
