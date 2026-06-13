# Bloom

A pre-configured Arch-based distro featuring Hyprland, developer tools, and other essential applications, built around a Hyprland-focused development workflow.

Bloom is not designed for beginners. While installation and day-to-day use are straightforward for users familiar with Linux, some knowledge of Arch Linux and the command line is expected! This distro is based off Arch after all, so expect to maintain your OWN system rather than having the system do it for you.

The included Hyprland dotfile is not maintained or made by this project. It is based on the open-source illogical-impulse project by end-4:

https://github.com/end-4/dots-hyprland

(check them out!)

# Building

If you want to build and compile Bloom yourself, you must already have installed Arch Linux. Then install `archiso`:

```
sudo pacman -S archiso
```

Clone and cd into the folder:

```
git clone https://github.com/auth1ery/bloom.git
cd bloom
```

Then build:

```
sudo mkarchiso -v -w /tmp/bloom-work -o /tmp/bloom-out ~/bloom
```

If you've already built it and want to build again, run the same command but delete the other Bloom folders first:

```
sudo rm -rf /tmp/bloom-work /tmp/bloom-out
sudo mkarchiso -v -w /tmp/bloom-work -o /tmp/bloom-out ~/bloom
```

Building may take a while.

More documentation can be avaliable at: https://bloom.cloudlull.fyi
