# KDE / Plasma configuration as code

This directory holds exported Plasma **theme + panel** configuration so it can be
committed and reproduced across machines. The suggested flow:

1. On a KDE Bazzite/Plasma device (e.g. the `deck-nvidia` image), run:

   ```sh
   ~/.scripts/setup/bazzite/kde-config-export.sh
   ```

2. It copies the non-secret Plasma config under `hosts/<hostname>/`:

   - `.config/plasma-org.kde.plasma.desktop-appletsrc` — panels + plasmoids + wallpaper
   - `.config/kdeglobals` — color scheme, fonts, general settings
   - `.config/kwinrc` / `kwinrulesrc` — window decorations, effects, per-window rules
   - `.local/share/color-schemes`, `plasma/look-and-feel`, `plasma/plasmoids`,
     `plasma/layout-templates`, `konsole`, `fonts`

3. Review/redact, then commit. Apply the same look elsewhere by copying the
   relevant `.config` / `.local/share` back onto the target.

> This is intentionally **not** wired into `fresh_install.sh`'s host flow: it is
> environment-specific (each Plasma box can differ) and device owners differ. It
> exists so a look that only exists on this machine can be turned into
> repeatable code. If a specific look should ship on every KDE image, move the
> relevant bits into the bazzite image recipe's `files/` layer instead and remove
> them from here.