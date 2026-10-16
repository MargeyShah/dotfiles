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

   This installs host GUI apps as **flatpaks** (Element, VS Code, Vesktop,
   Plexamp, osu!, Ludusavi, Heroic, Gear Lever), installs **Helium** and
   **Sidra** as AppImages (via Gear Lever — no Flathub package exists),
   creates an **Ubuntu Distrobox** container holding the apt CLI toolchain
   (rust, nvm, pyenv, starship, fzf, nvim, opencode, …), makes that container
   the default terminal, and symlinks the dotfiles. `podman-docker` (baked into
   the image) provides the `docker` CLI against Podman; there is no Docker
   daemon.

`setup/lib.sh` holds the shared helpers, app framework, and `dotfile_setup()`
used by both `fresh_install.sh` and `fresh_install_bazzite.sh`.
