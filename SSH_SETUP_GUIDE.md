# Arch & Omarchy Native SSH Key & Agent Setup Guide

This guide covers the native Arch Linux and Omarchy Quattro architecture for managing SSH keys. It sets up an on-demand, systemd-managed `ssh-agent` that synchronizes across all terminals, subshells, and GUI applications, requiring your passphrase only **once per login session**.

---

## 1. Architecture Overview

```
User Login / Session Start
       │
       ├──► systemd User Socket (ssh-agent.socket)
       │         │ (Listens on /run/user/1000/ssh-agent.socket)
       │         └──► Socket Activation ──► /usr/bin/ssh-agent -D (On-demand)
       │
       ├──► Session Environment (~/.config/environment.d/ssh-agent.conf)
       │         │ (Exports SSH_AUTH_SOCK to systemd, uwsm, Hyprland, GUI apps)
       │         └──► Inherited by all terminals (Ghostty, Foot, Alacritty, Kitty)
       │
       └──► OpenSSH Config (~/.ssh/config: AddKeysToAgent yes)
                 │
                 ├──► 1st SSH / Git command: Prompts for passphrase once
                 │         └──► Unlocked key loaded into systemd ssh-agent
                 │
                 └──► All subsequent commands: Instant auth across ALL terminals
```

### Why This Native Setup is Best Practice
- **Zero Third-Party Bloat:** No `keychain`, `ssh-ident`, or custom shell loops spawning unmanaged background processes.
- **On-Demand Socket Activation:** Handled by `openssh`'s built-in systemd user socket (`ssh-agent.socket`). The agent process starts only when accessed and remains alive across terminal windows and tabs.
- **Unified Session Socket:** Both CLI shells (`bash`, `zsh`) and Wayland/GUI apps (IDEs, GitKraken, VS Code) share the exact same socket path (`$XDG_RUNTIME_DIR/ssh-agent.socket`).
- **Single Passphrase Entry:** With `AddKeysToAgent yes`, OpenSSH automatically loads the key into the running agent upon first use, keeping it unlocked until you log out or reboot.

---

## 2. Step-by-Step Setup

### Step 1: Generate an Ed25519 SSH Key Pair

Modern best practice uses **Ed25519** (faster, shorter, and cryptographically superior to legacy RSA):

```bash
ssh-keygen -t ed25519 -C "your-email@example.com"
```

1. Press <kbd>Enter</kbd> to accept the default file path (`~/.ssh/id_ed25519`).
2. Enter a strong passphrase when prompted.
3. This generates two files:
   - Private key: `~/.ssh/id_ed25519` *(chmod `600`, keep secret)*
   - Public key: `~/.ssh/id_ed25519.pub` *(chmod `644`)*

---

### Step 2: Add Public Key to GitHub or Remote Servers

Print your public key:
```bash
cat ~/.ssh/id_ed25519.pub
```

#### Adding to GitHub:
1. Copy the output line (starts with `ssh-ed25519 ...`).
2. Go to **GitHub** → **Settings** → **SSH and GPG keys** → **New SSH key**.
3. Choose **Key type: Authentication Key** and paste your key.

*(Alternatively, if `gh` CLI is authenticated:)*
```bash
gh ssh-key add ~/.ssh/id_ed25519.pub --title "Omarchy Laptop"
```

#### Adding to a Remote Linux Server:
```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub user@server-ip
```

---

### Step 3: Enable the Arch-Native Systemd User Socket

Arch Linux packages the user socket directly inside the official `openssh` package. Enable and start it:

```bash
systemctl --user enable --now ssh-agent.socket
```

Verify that the socket is active and listening:
```bash
systemctl --user status ssh-agent.socket
```

You should see:
```text
● ssh-agent.socket - Socket for the OpenSSH key agent
     Active: active (listening)
     Listen: /run/user/1000/ssh-agent.socket (Stream)
```

---

### Step 4: Synchronize `SSH_AUTH_SOCK` Across the Entire Desktop

To ensure the socket path is available to systemd, Wayland compositors (Hyprland), terminal emulators, and GUI applications:

#### 1. Systemd User Session Configuration (`environment.d`):
```bash
mkdir -p ~/.config/environment.d
echo 'SSH_AUTH_SOCK="${XDG_RUNTIME_DIR}/ssh-agent.socket"' > ~/.config/environment.d/ssh-agent.conf
```

#### 2. Shell Configuration (`.bashrc` and `.zshrc`):
Ensure the following line is present near the top of both `~/.bashrc` and `~/.zshrc`:
```bash
export SSH_AUTH_SOCK="${XDG_RUNTIME_DIR:-/run/user/$UID}/ssh-agent.socket"
```

#### 3. Update the Live Session Environment (No Logout Required):
```bash
systemctl --user set-environment SSH_AUTH_SOCK="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/ssh-agent.socket"
```

---

### Step 5: Configure OpenSSH to Auto-Load on First Use

Configure OpenSSH client defaults in `~/.ssh/config`:

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh

cat <<'CFG' >> ~/.ssh/config
Host *
    AddKeysToAgent yes
    IdentityFile ~/.ssh/id_ed25519
CFG

chmod 600 ~/.ssh/config
```

#### What `AddKeysToAgent yes` does:
- You do **not** need to manually run `ssh-add` every time you boot.
- The first time you execute `git push`, `ssh <host>`, or an SSH operation, OpenSSH asks for your passphrase once in your terminal.
- OpenSSH immediately caches the decrypted key in the background `ssh-agent.socket`.
- Every other open terminal, new tab, background job, or editor will now authenticate without prompting again for the remainder of your login session.

---

## 3. Verification & Testing

### 1. Test Authentication
Test your connection against GitHub:
```bash
ssh -T git@github.com
```
Enter your passphrase once. You should see:
```text
Hi username! You've successfully authenticated, but GitHub does not provide shell access.
```

### 2. Verify Key is Cached in Agent
In any terminal window or tab, query the agent:
```bash
ssh-add -l
```
You should see your key listed:
```text
256 SHA256:... your-email@example.com (ED25519)
```

### 3. Optional: Manual Immediate Unlock
If you prefer to unlock the key immediately upon login without waiting for your first `git` command:
```bash
ssh-add
```

---

## 4. Troubleshooting & Maintenance

| Symptom | Cause | Resolution |
| :--- | :--- | :--- |
| `Permission denied (publickey)` | Public key not added to remote host or wrong file permissions | Run `chmod 700 ~/.ssh && chmod 600 ~/.ssh/*` |
| `Could not open a connection to your authentication agent` | `SSH_AUTH_SOCK` variable unset or `ssh-agent.socket` inactive | Run `systemctl --user enable --now ssh-agent.socket` and check `echo $SSH_AUTH_SOCK` |
| Agent asks for passphrase on every terminal | `AddKeysToAgent yes` missing from `~/.ssh/config` | Check `~/.ssh/config` contains `AddKeysToAgent yes` |
| Key not cleared on lock screen | Key lifetimes default to session lifetime | Set `AddKeysToAgent 4h` or lock explicitly with `ssh-add -x` |
