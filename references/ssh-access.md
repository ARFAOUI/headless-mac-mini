# Phase 1: local SSH access

Goal: `ssh mini` from the admin's main Mac, key-based, no prompts, usable by an agent.

## 1. Find the machine

```bash
ping -c 2 <ip>
nc -z -G 3 <ip> 22 && echo "SSH port open"
ssh -v -o BatchMode=yes nobody@<ip> true 2>&1 | grep "Authentications that can continue"
```

`<hostname>.local` works only on the same subnet. **mDNS does not cross VLANs** (unless your router
reflects it), so prefer the IP from a DHCP reservation.

## 2. Use a dedicated key without a passphrase

An agent cannot type a key passphrase, and an empty `ssh-agent` means a passphrase-protected key
is useless to it. Check:

```bash
ssh-keygen -y -P "" -f ~/.ssh/id_ed25519 >/dev/null 2>&1 && echo "no passphrase" || echo "has passphrase"
ssh-add -l
```

Symptom of this problem in `ssh -v`: `Server accepts key: ...` followed by `Permission denied`.
The key is installed; your side just cannot sign with it.

Simplest fix: a dedicated key for this one host.

```bash
ssh-keygen -t ed25519 -N "" -C "main-mac->mini" -f ~/.ssh/mini_ed25519
```

## 3. Install the key (human runs this in a real Terminal)

```bash
cat ~/.ssh/mini_ed25519.pub | ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no \
  <admin>@<ip> 'mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && echo KEY_INSTALLED'
```

Why these flags: without them, ssh first offers every key in the agent. Several keys means the
server says `Too many authentication failures` before you ever get a password prompt. Plain
`ssh-copy-id` hits this too.

## 4. Add an alias

`~/.ssh/config` on the main Mac:

```
Host mini
    HostName <reserved-ip>
    User <admin>
    IdentityFile ~/.ssh/mini_ed25519
    IdentitiesOnly yes
```

Add connection sharing, so agents that run many commands reuse one TCP connection. That is
faster, and it keeps router intrusion prevention from mistaking you for an SSH scanner:

```
    ControlMaster auto
    ControlPath ~/.ssh/cm/%r@%h:%p
    ControlPersist 10m
```

(`mkdir -m 700 ~/.ssh/cm` once.)

Verify non-interactively, the way an agent will use it:

```bash
ssh -o BatchMode=yes mini 'echo OK; hostname; sw_vers -productVersion'
```

## Remote Login is admin-only by default

macOS restricts SSH to the `com.apple.access_ssh` group, which by default nests the `admin` group.
A standard user gets `Connection closed` and the log shows
`pam_sacl: denying '<user>' due to failed service ACL check`. Fix:

```bash
sudo dseditgroup -o edit -a <user> -t user com.apple.access_ssh
```
