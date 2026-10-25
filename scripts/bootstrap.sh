#!/bin/bash
# Phase 3 + 4: power, firewall, Command Line Tools, Homebrew, git, Node, Claude Code, Tailscale.
# Run on the Mac as the ADMIN user, with passwordless sudo available (see references/bootstrap.md):
#   ssh mini 'bash -s' < scripts/bootstrap.sh
# Idempotent: safe to run again. Prints a Tailscale login URL at the end if not signed in yet.
set -euo pipefail

if ! sudo -n true 2>/dev/null; then
  echo "sudo needs a password. Create the temporary sudoers file first (references/bootstrap.md)." >&2
  exit 1
fi

TS_HOSTNAME="${TS_HOSTNAME:-$(scutil --get LocalHostName)}"

echo "==> Power"
sudo pmset -a sleep 0 autorestart 1 womp 1

echo "==> Firewall"
F=/usr/libexec/ApplicationFirewall/socketfilterfw
sudo $F --setglobalstate on >/dev/null
sudo $F --setallowsigned on >/dev/null
sudo $F --setallowsignedapp on >/dev/null

echo "==> Command Line Tools"
if ! xcode-select -p >/dev/null 2>&1; then
  FLAG=/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  sudo touch "$FLAG"
  PKG=$(softwareupdate -l 2>/dev/null | grep -E "\*.*Command Line Tools" | sed -E 's/^.*Label: //; s/^ *\* *//' | sort -V | tail -1)
  [ -n "$PKG" ] || { echo "No Command Line Tools package offered by softwareupdate" >&2; exit 1; }
  sudo softwareupdate -i "$PKG"
  sudo rm -f "$FLAG"
fi

echo "==> Homebrew"
if [ ! -x /opt/homebrew/bin/brew ]; then
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
grep -q "brew shellenv" ~/.zprofile 2>/dev/null || echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"

echo "==> git, node, tailscale"
brew install git node tailscale

echo "==> Claude Code"
command -v "$HOME/.local/bin/claude" >/dev/null || curl -fsSL https://claude.ai/install.sh | bash
grep -q '.local/bin' ~/.zprofile || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zprofile

echo "==> Tailscale (system service)"
sudo brew services start tailscale >/dev/null
sleep 3
if ! tailscale ip -4 >/dev/null 2>&1; then
  echo "Open the URL below and sign in:"
  sudo tailscale up --hostname="$TS_HOSTNAME" --timeout=10s || true
fi

echo "==> Done"
"$HOME/.local/bin/claude" --version; node --version; git --version; tailscale ip -4 2>/dev/null || true
