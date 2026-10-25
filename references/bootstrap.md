# Phase 3: system settings and toolchain

Everything here needs `sudo`. Agents cannot type the password, so either the human runs each
step, or the human creates a **temporary** passwordless sudoers file once:

```bash
ssh -t mini 'echo "<admin> ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/zz-setup >/dev/null && sudo chmod 440 /etc/sudoers.d/zz-setup && echo SUDO_OK'
```

**Delete it in phase 8.** (`sudo rm /etc/sudoers.d/zz-setup`)

Then run `scripts/bootstrap.sh` on the Mac, or the steps below one at a time.

## Power

```bash
sudo pmset -a sleep 0            # never sleep
sudo pmset -a autorestart 1      # start up after power failure
sudo pmset -a womp 1             # wake on network
pmset -g | grep -E "^ (sleep|autorestart|womp)"
```

## Firewall

```bash
F=/usr/libexec/ApplicationFirewall/socketfilterfw
sudo $F --setglobalstate on
sudo $F --setallowsigned on        # Apple services such as sshd and Screen Sharing keep working
sudo $F --setallowsignedapp on
```

Open a **new** SSH session afterwards and check port 5900 (Screen Sharing) before moving on.
Stealth mode is optional; it also stops ping, which makes debugging from another machine harder.

## Command Line Tools, headless

`xcode-select --install` opens a GUI dialog. Over SSH, use Software Update instead:

```bash
sudo touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
PKG=$(softwareupdate -l 2>/dev/null | grep -E "\*.*Command Line Tools" | sed -E 's/^.*Label: //; s/^ *\* *//' | sort -V | tail -1)
sudo softwareupdate -i "$PKG" --verbose
sudo rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
xcode-select -p
```

## Homebrew, git, Node

```bash
NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"
brew install git node
```

`NONINTERACTIVE=1` still needs sudo without a prompt, which is what the temporary sudoers file is for.

## Claude Code

```bash
curl -fsSL https://claude.ai/install.sh | bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zprofile
```

This installs per user into `~/.local/bin`. Install it again as the agent user in phase 5.

## Full Xcode without an Apple ID download

If another Mac already has the right Xcode, copy it instead of downloading ~10 GB with an Apple ID.
`/Applications` is writable by the admin group, so no sudo is needed for the copy itself, and
`ditto` keeps the code signature intact:

```bash
ditto -c /Applications/Xcode.app - | ssh mini 'mkdir -p /Applications/Xcode.app && ditto -x - /Applications/Xcode.app && codesign --verify --deep --strict /Applications/Xcode.app && echo ok'
ssh -t mini 'sudo xcode-select -s /Applications/Xcode.app && sudo xcodebuild -license accept && sudo xcodebuild -runFirstLaunch'
```

Signing for a device still needs an Apple ID in Xcode > Settings > Accounts **as the user that
builds** (the agent user), which means one Screen Sharing session (see agent-user.md).

## Containers (only if needed)

OrbStack (`brew install --cask orbstack`) is lighter than Docker Desktop. Both need a GUI login
session once to finish setup, so do this while Screen Sharing is available.
