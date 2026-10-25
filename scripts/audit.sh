#!/bin/bash
# Read-only health check of a headless Mac. Run on the Mac, or: ssh mini 'bash -s' < scripts/audit.sh
# Prints OK / FIX lines. Changes nothing.

ok()  { printf "  OK   %s\n" "$*"; }
fix() { printf "  FIX  %s\n" "$*"; }
hdr() { printf "\n%s\n" "$*"; }

PATH="/opt/homebrew/bin:$HOME/.local/bin:$PATH"

hdr "Machine"
echo "  $(scutil --get ComputerName 2>/dev/null) | $(sysctl -n hw.model) | macOS $(sw_vers -productVersion) | $(($(sysctl -n hw.memsize) / 1073741824)) GB | $(df -h / | awk 'NR==2{print $4" free"}')"
echo "  user: $(whoami)  console: $(stat -f %Su /dev/console)  uptime:$(uptime | sed 's/.*up/ /; s/, [0-9]* user.*//')"

hdr "Boot and power"
fdesetup status | grep -q "Off" && ok "FileVault off (unattended reboot possible)" || fix "FileVault is on: reboots will stop at the unlock screen"
[ "$(pmset -g | awk '$1=="sleep"{print $2}')" = "0" ] && ok "System sleep off" || fix "System sleep enabled: sudo pmset -a sleep 0"
[ "$(pmset -g | awk '$1=="autorestart"{print $2}')" = "1" ] && ok "Restart after power failure" || fix "autorestart off: sudo pmset -a autorestart 1"
AL=$(defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser 2>/dev/null)
[ -n "$AL" ] && ok "Auto-login user: $AL" || fix "No auto-login user: user services will not start after reboot"

hdr "Remote access"
launchctl print system/com.openssh.sshd >/dev/null 2>&1 && ok "Remote Login (SSH) on" || fix "Remote Login off"
launchctl print system/com.apple.screensharing >/dev/null 2>&1 && ok "Screen Sharing on (fallback)" || fix "Screen Sharing off: no fallback if SSH breaks"
CONF=$(cat /etc/ssh/sshd_config /etc/ssh/sshd_config.d/* 2>/dev/null)
echo "$CONF" | grep -qiE "^\s*PasswordAuthentication\s+no" && ok "SSH password login disabled" || fix "SSH password login still allowed (see hardening.md)"
if command -v tailscale >/dev/null; then
  TS=$(tailscale ip -4 2>/dev/null)
  [ -n "$TS" ] && ok "Tailscale up: $TS" || fix "Tailscale installed but not connected: sudo tailscale up"
else
  fix "Tailscale not installed"
fi

hdr "Security"
/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate | grep -q "enabled" && ok "Firewall on" || fix "Firewall off"
ls /etc/sudoers.d/ 2>/dev/null | grep -q . && fix "Files in /etc/sudoers.d: $(ls /etc/sudoers.d | tr '\n' ' ')(remove temporary NOPASSWD when done)" || ok "No extra sudoers files"
for u in $(dscl . -list /Users UniqueID | awk '$2>=501{print $1}'); do
  dseditgroup -o checkmember -m "$u" admin >/dev/null 2>&1 && role=admin || role=standard
  perm=$(stat -f %Lp "/Users/$u" 2>/dev/null)
  [ "$perm" = "700" ] && ok "User $u ($role), home 700" || fix "User $u ($role), home $perm: other users may read it (chmod 700)"
done

hdr "Network"
for dev in $(networksetup -listallhardwareports | awk '/Device:/{print $2}'); do
  ip=$(ipconfig getifaddr "$dev" 2>/dev/null)
  [ -n "$ip" ] && echo "  $dev  $ip  $(ifconfig "$dev" | awk '/ether/{print $2}')"
done

hdr "Toolchain"
xcode-select -p >/dev/null 2>&1 && ok "Command Line Tools" || fix "Command Line Tools missing"
for t in brew git node claude; do
  command -v $t >/dev/null && ok "$t $($t --version 2>/dev/null | head -1)" || fix "$t missing"
done
