# macOS updates on a headless Mac

Minor updates are easy. **Major upgrades over SSH are where headless Macs get stuck.** This page
is what we hit going from macOS 26.5 to 27.0.1 on an M4 Mac mini, and what to do instead.

## Control when updates happen

With "Install macOS updates" on, the Mac installs **minor** updates and restarts by itself. With
FileVault off and auto-login on, it comes back unattended. **Major** upgrades always need
someone to approve them.

To hold everything until you choose a moment (for example while other work depends on the box):

```bash
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates -bool false
# and afterwards:
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates -bool true
```

List what is offered: `softwareupdate -l` (note the exact `Label:`).

## Apple silicon needs the owner password

On Apple silicon, installing an OS update requires the password of a **volume owner** (an admin
user who has a Secure Token, usually the first account). `sudo` alone is not enough, and NOPASSWD
sudoers does not help. The agent cannot type it: hand the human a command that reads it without
echoing and passes it on stdin:

```bash
ssh -t mini 'read -s "P?password: "; echo; printf "%s" "$P" | sudo softwareupdate -i "<label>" --agree-to-license -R --user <admin> --stdinpass --verbose'
```

## The install waits for the console user to log out

On a machine with **auto-login**, the command above authenticates and then only **queues** the
upgrade "for post-logout install". It does not restart, even with `-R`. The install starts when
the logged-in console user logs out, and on a headless box nobody ever does.

Trigger it by ending the console user's session (as admin, after the queue was committed):

```bash
ssh mini 'grep "Successfully committed stash" /var/log/install.log | tail -1'   # confirm it is queued
ssh mini 'uid=$(id -u $(stat -f %Su /dev/console)); sudo launchctl bootout gui/$uid'
ssh mini 'grep "Post Logout" /var/log/install.log | tail -1'   # installer progress phase started
```

Seconds later the log shows `IASPPhase: 'Software Update Post Logout'` and the Mac prepares,
restarts and installs on its own. Logging out kills that user's apps, so stop agent jobs first.

_Tested 2026-10-25, 26.5 to 27.0.1 on an M4 Mac mini: after the logout the Mac was offline for about 4 minutes, came back on 27.0.1 by itself and auto-logged in the agent user. FileVault off, auto-login, `/etc/kcpassword`, Tailscale, Homebrew and the old Command Line Tools all survived._

## What went wrong, and why

| Step | What happened | Lesson |
|---|---|---|
| `sudo softwareupdate --download "<label>"` | Downloaded 100%, then `Failed to authenticate` | Downloading in the background works, but preparing the update needs owner auth. Fine to pre-download; it is not staged yet. |
| `softwareupdate -i "<label>" -R --user <admin> --stdinpass` | Authenticated, logged `Queueing updates for post-logout install ... Successfully committed stash`, then **never restarted** | The install is waiting for the console user (auto-login) to log out. |
| `sudo shutdown -r now` to "kick" the queued install | Back in 15 seconds on the old version; the queued install was gone | A plain restart does not run a queued post-logout install. Do not do this. |
| Same command again, adding `--agree-to-license` | Exactly the same: queued, no restart | Not the cause. Keep the flag (it avoids a license prompt), but it does not trigger the install. |
| `sudo launchctl bootout gui/<console-uid>` after queueing | Installer started its "Software Update Post Logout" phase within seconds | **This is the fix.** See the section above. |

## Reliable fallback: the full installer

`startosinstall` is built for unattended upgrades and restarts the Mac itself:

```bash
sudo softwareupdate --fetch-full-installer --full-installer-version <version>    # ~16 GB into /Applications
ssh -t mini 'read -s "P?password: "; echo; printf "%s" "$P" | sudo "/Applications/Install macOS <Name>.app/Contents/Resources/startosinstall" \
  --agreetolicense --forcequitapps --nointeraction --user <admin> --stdinpass'
```

## Watching it from another machine

The Mac goes offline for 20 to 40 minutes and may restart more than once. Poll instead of
waiting blindly, and check the version, not just "it answers ping":

```bash
until v=$(ssh -o BatchMode=yes -o ConnectTimeout=5 mini 'sw_vers -productVersion' 2>/dev/null) && [ "$v" != "<old-version>" ]; do sleep 20; done; echo "now on $v"
```

If it answers on the old version with a short uptime, the install did not run: read
`/var/log/install.log` from the time of the attempt.

## After a major upgrade

1. Run `scripts/audit.sh`.
2. **Command Line Tools**: they survived 26 to 27 for us, but a matching new version showed up in
   `softwareupdate -l` (`Command Line Tools for Xcode 27.0`). Install it with
   `sudo softwareupdate -i "<label>"`, or reinstall with the headless method in `bootstrap.md` if they are gone.
3. `brew update && brew upgrade` and `brew doctor`, then check Tailscale is connected (`tailscale status`).
4. Confirm auto-login still points at the agent user and `/etc/kcpassword` still exists.
5. Check for a "finish setting up" screen with Screen Sharing if the console user looks stuck.
6. Turn automatic updates back on.
