# Scripts

Various scripts to automate tasks, simplify repetitive configuration, etc.

Please make sure to clone this project directly into the HOME directory of the current user.

```
mv dotfiles .dotfiles
cd .dotfiles/setup
./fresh_install.sh # option 1 for servers, 2 for linux/mac devices, 3 is fully personal, ignore, 4 for dotfile setup alone (will run into issues if you've never ran 2 on your device

```

`nvimup` will update nvim configs from the https://github.com/joermo/dotfiles remote

## Bazzite

Bazzite is image-based (rpm-ostree), so it does **not** use `fresh_install.sh`
(which refuses to run there). Instead:

1. **Custom image** — `github.com/MargeyShah/bazzite` builds flatpak-first
   Bazzite images (gnome / gnome-nvidia-open / deck-gnome / deck-nvidia-gnome).
   Rebase once (see that repo's README), keeping upstream Bazzite updates.
2. **Bootstrap** — on the host, run:

   ```
   ~/.scripts/setup/fresh_install_bazzite.sh
   ```

   This installs host GUI apps as **flatpaks** (Element, VS Code, Signal,
   Vesktop, Plexamp, osu!, Ludusavi, Heroic, Gear Lever, Prism Launcher, Cemu,
   RPCS3, Dolphin, XIVLauncher), installs **Helium** and **Sidra** as AppImages
   (via Gear Lever — no Flathub package exists),
   creates an **Ubuntu Distrobox** container holding the apt CLI toolchain
   (rust, nvm, pyenv, starship, fzf, nvim, opencode, …), makes that container
   the default terminal, and symlinks the dotfiles. `podman-docker` (baked into
   the image) provides the `docker` CLI against Podman; there is no Docker
   daemon.

   Gaming extras are installed automatically (every target host is a gaming
   host; skip with `--no-gaming`): **EmuDeck** (`ujust get-emudeck install`),
   **Decky Loader** (`ujust setup-decky install`), **Bazzite Buddy**
   (`ujust get-decky-bazzite-buddy install`), and these **Decky plugins** from
   the Decky store: CSS Loader, SteamGridDB, ProtonDB Badges, HLTB for Deck,
   TabMaster, PlayCount, IsThereAnyDeal for Deck, Decky LSFG-VK, AutoFlatpaks,
   Decky Terminal, Audio Loader, Game Theme Music, Quick Launch, Volume Mixer,
   EmuDecky, and MusicControl.

   **System extras** are also installed automatically (skip with `--no-extras`):
   Proton Plus, Sunshine, Wake-on-LAN (`ujust wol enable`), Boot-to-Windows from
   Steam, Virtualization (`ujust setup-virtualization virt-on`), input group
   (`ujust add-user-to-input-group add`), CoolerControl (layers rpm; reboot),
   LM Studio + VSCodium (Homebrew casks from `ublue-os/tap`), and Android
   Platform Tools (adb/fastboot, inside the Distrobox).

`setup/lib.sh` holds the shared helpers, app framework, and `dotfile_setup()`
used by both `fresh_install.sh` and `fresh_install_bazzite.sh`.

## SSH & commit signing

Every install (both scripts) runs `app_ssh`: it generates an `~/.ssh/id_ed25519`
if absent, copies it to **pistachio** (`margey@192.168.0.2`), registers it on
GitHub via `gh` (best-effort), and configures git to **sign commits with SSH**
(`gpg.format=ssh`, `commit.gpgsign=true`) so they show as *Verified*. The
managed `~/.ssh/config` (`dotfiles/ssh/config`) defines the `pistachio` host.
