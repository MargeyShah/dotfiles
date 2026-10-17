# Scripts

Various scripts to automate tasks, simplify repetitive configuration, etc.

Please make sure to clone this project as `~/.scripts` — the setup scripts
resolve their own files from `$HOME/.scripts`:

```
git clone https://github.com/MargeyShah/dotfiles.git ~/.scripts
cd ~/.scripts/setup
./fresh_install.sh   # 1 server, 2 Unix PC (Linux desktop), 3 disney (Mac work), 4 dotfiles only
```

(Option 4 installs/symlinks the dotfiles alone and assumes the profile from
option 2 has already provisioned the toolchain — it will run into issues on a
machine where that was never done.)

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
   Vesktop, Plexamp, Hidamari, osu!, Ludusavi, Heroic, Gear Lever, Prism
   Launcher, Cemu, RPCS3, Dolphin, XIVLauncher), installs **Helium** and
   **Sidra** as AppImages
   (via Gear Lever — no Flathub package exists),
   creates an **Ubuntu Distrobox** container holding the apt CLI toolchain
   (rust, nvm, pyenv, starship, fzf, nvim, opencode, …), makes that container
   the default terminal, and symlinks the dotfiles. `podman-docker` (baked into
   the image) provides the `docker` CLI against Podman; there is no Docker
   daemon.

   **Default terminal** is a Ptyxis profile using "Use Custom Command" =
   `distrobox enter bazzite-ubuntu -- zsh -l` (host container, custom command —
   not `default-container`, which ignores a custom shell). Inside the box,
   `$SHELL` is forced to `/usr/bin/zsh` via `/etc/zsh/zshenv` so every tool
   (zellij panes, nvim `:term`, …) agrees; zellij's `default_shell "zsh"` is
   pinned in the managed `~/.config/zellij/config.kdl`. Use `dbt` (an fzf menu,
   like `q()`) to switch between the host shell and any Distrobox.

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

   Element gets a user flatpak override for keyring support on GNOME:
   `flatpak override --user --talk-name=org.freedesktop.secrets im.riot.Riot`.

   **Hanabi** (the GNOME Shell live-wallpaper extension used with Hidamari) is
   not on Flathub or extensions.gnome.org, so it is not installed automatically.
   To add it manually, clone [jeffshee/gnome-ext-hanabi](https://github.com/jeffshee/gnome-ext-hanabi)
   (use the `javascript` branch for GNOME 45–50, `main` for GNOME 50+), then run
   `make install` and enable it in the Extensions app.

`setup/lib.sh` holds the shared helpers, app framework, and `dotfile_setup()`
used by both `fresh_install.sh` and `fresh_install_bazzite.sh`.

## SSH & commit signing

Every install (both scripts) runs `app_ssh`: it generates an `~/.ssh/id_ed25519`
if absent and configures git to **sign commits with SSH** (`gpg.format=ssh`,
`commit.gpgsign=true`) so they show as *Verified*.

Copying that key to **pistachio** (`margey@192.168.0.2`) and registering it on
GitHub via `gh` (best-effort) are **only done on our own machines** — the
hostnames listed in `dotfiles/zsh/env.zsh` (`HOSTS_WSL`/`HOSTS_LINUX`/`HOSTS_MAC`,
including `Element-Bazzite`). `gh` is never auto-authenticated; if `gh` is not
already logged in, the key push is skipped with a note. The managed
`~/.ssh/config` (`dotfiles/ssh/config`) defines the `pistachio` host.
