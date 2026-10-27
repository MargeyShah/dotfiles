# Scripts

Various scripts to automate tasks, simplify repetitive configuration, etc.

Please make sure to clone this project as `~/.scripts` — the setup scripts
resolve their own files from `$HOME/.scripts`:

```
git clone https://github.com/MargeyShah/dotfiles.git ~/.scripts
cd ~/.scripts/setup
./fresh_install.sh   # 1 server, 2 Unix PC (Linux desktop), 3 disney (Mac work), 4 dotfiles only
```

Option 4 (`--profile dotfiles`) installs the shared dependency set and symlinks
the dotfiles, without the desktop/server extras. It is the profile the Bazzite
Distrobox is provisioned with.

`nvimup` will update nvim configs from the https://github.com/joermo/dotfiles remote

## Prompt

`starship` uses the managed `dotfiles/.config/starship.toml` (symlinked to
`~/.config/starship.toml`). It only overrides one thing: the `container` module
— the `⬢ [name]` badge shown inside a Distrobox, which is **red** by default —
is recoloured **green**. Everything else (the `<user> in <host> in <dir>`
layout) stays at starship's defaults.

## Host-gated config

`dotfiles/zsh/env.zsh` holds the hostname lists (`HOSTS_WSL`, `HOSTS_LINUX`,
`HOSTS_MAC`) and the `is_env` / `is_linux_desktop` / `is_server` / `is_work_mac`
helpers. Per-host settings are gated on those lists rather than on the physical
OS, e.g. the LM Studio `lms` PATH entry in `dotfiles/zsh/config.zsh` only applies
on `HOSTS_LINUX` hosts.

## Bazzite

Bazzite is image-based (rpm-ostree), so `fresh_install.sh` is **not** run on the
host (it refuses to). Instead the bootstrap below creates an Ubuntu Distrobox and
runs `fresh_install.sh --profile dotfiles` *inside* it. Steps:

1. **Custom image** — `github.com/MargeyShah/bazzite` builds flatpak-first
   Bazzite images (gnome / gnome-nvidia-open / deck-gnome / deck-nvidia-gnome).
   Rebase once (see that repo's README), keeping upstream Bazzite updates.
2. **Bootstrap** — on the host, run:

   ```
   ~/.scripts/setup/fresh_install_bazzite.sh
   ```

   The **GUI apps are baked into the image** (`default-flatpaks` in the
   MargeyShah/bazzite recipes: Element, VS Code, Signal, Plexamp, Hidamari,
   osu!, Ludusavi, Heroic, Gear Lever, Flameshot, Proton Plus, Sunshine, Prism
   Launcher, Cemu, RPCS3, Dolphin, XIVLauncher), so the bootstrap does not
   re-install them. It only:

   - installs **Helium**, **Sidra**, **Ghostty** and **Vesktop** as AppImages in
     `~/AppImages` via Gear Lever (none has a suitable Flathub package; Gear
     Lever is the recommended way to manage AppImages). Download and integration
     are checked independently, so a re-run only does the missing step,
   - grants **Flameshot** the screenshot portal permission
     (`flatpak permission-set screenshot screenshot org.flameshot.Flameshot yes`;
     per-user, so it cannot be baked into the image),
   - installs **zsh** on the host with Homebrew (never rpm-ostree) and makes it
     the login shell via `usermod -s` (there is no `chsh` on Bazzite),
   - creates the **Ubuntu Distrobox** and provisions it by running
     `setup/fresh_install.sh --profile dotfiles` inside it — the same script and
     app list as any other host, no Bazzite-specific copy. As a Distrobox
     shares `$HOME`, that also symlinks the dotfiles for the host.

   `podman-docker` (baked into the image) provides the `docker` CLI against
   Podman; there is no Docker daemon.

   **Terminals are not modified by the bootstrap.** No Ptyxis profile is written
   and no shell rc file is touched. Enter the toolchain on demand with
   `distrobox enter bazzite-ubuntu`, or run `box` (an fzf picker of every
   Distrobox; it enters straight away when only one exists).

   **Terminal flow:** a new window opens a **host zsh**
   (Ptyxis profile: Container = `session`, Custom Command =
   `/home/linuxbrew/.linuxbrew/bin/zsh -l`). That host shell auto-starts
   **zellij**, and zellij's `default_shell` is
   `dotfiles/.config/zellij/box-shell`, so **every pane runs inside
   `bazzite-ubuntu`**. `distrobox enter` runs as a child of that wrapper (no
   `exec`), so `exit` in the box falls back to a **host zsh in the same pane**;
   `exit` again closes the pane. `box` is still there for ad-hoc use.

   zellij never runs inside the container: `is_server()` in `env.zsh` returns
   true when `$CONTAINER_ID` is set (which needs no distrobox binary, so it is
   safe on hosts without it). The zellij config is only symlinked on **Linux
   desktop** hosts (not servers, not mac) by `dotfile_config`.

   **GNOME Shell extensions** are installed *and* default-enabled by the image
   (the `gnome-extensions` + `gschema-overrides` modules), so the bootstrap does
   not touch them. The **Element keyring override** and the **window-manager
   defaults** are baked in the same way (`files` + `gschema-overrides`).

   The script is intentionally a thin harness: everything declarative lives in
   the image; it only does per-user/post-install work and the container.

   Gaming extras are installed automatically (every target host is a gaming
   host; skip with `--no-gaming`): **EmuDeck** (`ujust get-emudeck install`),
   **Decky Loader** (`ujust setup-decky install`), **Bazzite Buddy**
   (`ujust get-decky-bazzite-buddy install`), and these **Decky plugins** from
   the Decky store: CSS Loader, SteamGridDB, ProtonDB Badges, HLTB for Deck,
   TabMaster, PlayCount, IsThereAnyDeal for Deck, Decky LSFG-VK, AutoFlatpaks,
   Decky Terminal, Audio Loader, Game Theme Music, Quick Launch, Volume Mixer,
   EmuDecky, and MusicControl.

   **System extras** are also installed automatically (skip with `--no-extras`):
   Wake-on-LAN (`ujust wol enable`), Boot-to-Windows from Steam, Virtualization
   (`ujust setup-virtualization virt-on`), input group
   (`ujust add-user-to-input-group add`), and LM Studio + VSCodium (Homebrew
   casks from `ublue-os/tap`). Proton Plus, Sunshine and CoolerControl are baked
   into the image instead — CoolerControl is an rpm-ostree layer, so **reboot
   once after rebasing** to activate it. Android Platform Tools (adb/fastboot)
   are part of the regular dotfiles dependency set and so are installed inside
   the Distrobox.

   **Hanabi** (the GNOME Shell live-wallpaper extension used with Hidamari) is
   not on Flathub or extensions.gnome.org, so it is not installed automatically.
   To add it manually, clone [jeffshee/gnome-ext-hanabi](https://github.com/jeffshee/gnome-ext-hanabi)
   (use the `javascript` branch for GNOME 45–50, `main` for GNOME 50+), then run
   `make install` and enable it in the Extensions app.

`setup/lib.sh` holds the shared helpers, app framework, and `dotfile_setup()`
used by both `fresh_install.sh` and `fresh_install_bazzite.sh`. Its idempotency
checks (`appimage_downloaded`, `appimage_integrated`, `ujust_installed`,
`decky_plugin_installed`) let either script skip work that is already done —
`appimage_integrated` asks Gear Lever itself (`--list-installed --json`) rather
than guessing from filenames.

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
