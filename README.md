# Omarchy Quattro Personal Dotfiles & Configurations

This repository captures all user customizations structured strictly according to Omarchy Quattro standards:

* **Hyprland Window Manager (`.config/hypr/`)**:
  * Custom keybindings (`bindings.lua`):
    * `F7` (`SUPER + P` / `XF86Display`) → Toggles `crmne.hyprmoncfg` display manager.
    * `F8` (`SUPER + L`) → Locks the screen (`omarchy-system-lock`).
    * `ALT + SPACE` → Application launcher.
    * `SUPER + SHIFT + S` → Screen capture.
  * Window rules for Android Emulator / QEMU floating & full opacity.
  * Input & Look'n'Feel personal overrides.
* **Omarchy Shell & Plugins (`.config/omarchy/`) (Optional)**:
  * Full top bar layout & widget configurations (`shell.json`).
  * Custom themes (`awsm-changi`, `luminous`, `sora-koi`).
  * Menu extensions (`omarchy-menu.jsonc`).
  * Automation hooks (`theme-set`).
* **Audio & Hardware Autoswitching (`.config/wireplumber/` & `.local/share/wireplumber/`)**:
  * WirePlumber 0.5 sink priority rules (`50-alsa-output-priority.conf`):
    * Headphones: Priority `1500`
    * Internal Speakers: Priority `1200`
    * HDMI Monitors: Priority `600` (prevents external displays from stealing audio)
  * Dynamic hardware jack autoswitcher (`sof-autoswitch.lua`).
  * Bluetooth A2DP autoconnect rules.
* **Terminals & Shell Tools**:
  * Ghostty, Alacritty, Kitty, Foot terminal configs.
  * Starship prompt, Btop, Lazygit, Git config.
  * `.bashrc` & `.zshrc`.

---

## Installation on Another Omarchy Machine

### 1. Clone the repository
```bash
git clone <your-repo-url> ~/dotfiles
cd ~/dotfiles
```

### 2. Run the installer
```bash
./install.sh
```

### What `install.sh` does automatically:
1. Backs up any existing conflicting configs to `~/.dotfiles-backup/<timestamp>/`.
2. Deploys `.config` and `.local` files into place.
3. Automatically adds and enables all third-party shell plugins via the official Omarchy CLI (`omarchy plugin add ... --enable`).
4. Checks and installs required AUR packages (`hyprmoncfg`, `brave-origin-bin`).
5. Reloads Hyprland, WirePlumber, and the Omarchy Shell.

---

## Security & Omarchy Update Safety
* **Zero System Touches**: All configs live strictly in `$HOME/.config/` and `$HOME/.local/`.
* **Update Safe**: Running `omarchy update` on Omarchy Quattro will never overwrite your personal configurations.
* **No Secrets Committed**: API tokens, credentials, and private keys are excluded and stored in standard local state paths (`~/.local/state/`).

---

## Devices in use:
* **Acer sfg14-71**: The main work laptop.
* **Headless Realme Slimbook**: The converted at home PC.
