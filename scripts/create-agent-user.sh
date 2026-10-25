#!/bin/bash
# Phase 5: create a non-admin agent user, allow it over SSH, make it the auto-login user.
# Run on the ADMIN's main Mac (not on the mini). Needs passwordless sudo on the mini.
#
#   scripts/create-agent-user.sh <ssh-alias-of-admin> <mini-ip> [agent-username]
#
# Creates locally: ~/.ssh/<user>_<alias>_ed25519 and a Keychain item "<alias>-<user>".
set -euo pipefail

ADMIN_ALIAS="${1:?ssh alias for the admin account, e.g. mini}"
HOST_IP="${2:?IP the mini is reachable at}"
AGENT="${3:-agent}"
HERE="$(cd "$(dirname "$0")" && pwd)"
KEY="$HOME/.ssh/${AGENT}_${ADMIN_ALIAS}_ed25519"
KC="${ADMIN_ALIAS}-${AGENT}"

ssh -o BatchMode=yes "$ADMIN_ALIAS" 'sudo -n true' || { echo "No passwordless sudo on $ADMIN_ALIAS" >&2; exit 1; }
if ssh "$ADMIN_ALIAS" "id $AGENT" >/dev/null 2>&1; then echo "User $AGENT already exists" >&2; exit 1; fi

echo "==> Password into the local Keychain ($KC)"
PW=$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-24)
security add-generic-password -U -s "$KC" -a "$AGENT" -l "$KC auto-login password" -w "$PW"

echo "==> SSH key $KEY"
[ -f "$KEY" ] || ssh-keygen -t ed25519 -N "" -C "${ADMIN_ALIAS}-${AGENT}" -f "$KEY" -q
PUB=$(cat "$KEY.pub")

echo "==> Create user, lock admin home, SSH access"
# remote steps go over as a file; stdin carries the password, so it stays out of ssh command lines
# and shell history (sysadminctl itself still takes it as an argument for a moment, unavoidable)
REMOTE_SH=$(mktemp)
cat > "$REMOTE_SH" <<'REMOTE'
set -euo pipefail
read -r PW
sudo chmod 700 "$HOME"
sudo sysadminctl -addUser "$AGENT" -fullName "Agent" -password "$PW" -home "/Users/$AGENT" 2>&1 | grep -v "Assigning\|not created" || true
sudo createhomedir -c -u "$AGENT" >/dev/null
sudo chmod 700 "/Users/$AGENT"
sudo dseditgroup -o edit -a "$AGENT" -t user com.apple.access_ssh
sudo mkdir -p "/Users/$AGENT/.ssh"
echo "$PUB" | sudo tee "/Users/$AGENT/.ssh/authorized_keys" >/dev/null
sudo chown -R "$AGENT:staff" "/Users/$AGENT/.ssh"
sudo chmod 700 "/Users/$AGENT/.ssh"; sudo chmod 600 "/Users/$AGENT/.ssh/authorized_keys"
sudo sysadminctl -autologin set -userName "$AGENT" -password "$PW" 2>&1 | grep -i error || true
REMOTE
scp -q "$REMOTE_SH" "$ADMIN_ALIAS:/tmp/create-agent-remote.sh"; rm -f "$REMOTE_SH"
printf '%s\n' "$PW" | ssh "$ADMIN_ALIAS" "AGENT='$AGENT' PUB='$PUB' bash /tmp/create-agent-remote.sh; rm -f /tmp/create-agent-remote.sh"

echo "==> Auto-login password file (sysadminctl -autologin is unreliable)"
scp -q "$HERE/write-kcpassword.py" "$ADMIN_ALIAS:/tmp/write-kcpassword.py"
printf '%s\n' "$PW" | ssh "$ADMIN_ALIAS" "sudo /usr/bin/python3 /tmp/write-kcpassword.py \
  && sudo defaults write /Library/Preferences/com.apple.loginwindow autoLoginUser '$AGENT' \
  && rm /tmp/write-kcpassword.py"

echo "==> Agent environment + Claude Code"
ssh -o IdentitiesOnly=yes -i "$KEY" "$AGENT@$HOST_IP" 'cat > ~/.zprofile <<"EOF"
eval "$(/opt/homebrew/bin/brew shellenv)"
export PATH="$HOME/.local/bin:$PATH"
EOF
source ~/.zprofile; curl -fsSL https://claude.ai/install.sh | bash >/dev/null; ~/.local/bin/claude --version'

cat <<EOF

Add to ~/.ssh/config:

Host ${ADMIN_ALIAS}-${AGENT}
    HostName $HOST_IP
    User $AGENT
    IdentityFile $KEY
    IdentitiesOnly yes

Then reboot and verify (references/agent-user.md, step 8).
EOF
