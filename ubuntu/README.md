# ubuntu/

Bootstrap for an Ubuntu machine you administer: a workstation or an
always-on dev host where you have sudo, apt, and systemd.

For a rootless box such as a k8s dev pod, use [`linux/`](../linux/README.md)
instead.

## Usage

```sh
sudo apt-get install -y git
git clone https://github.com/mynk93/dotfiles.git ~/.dotfiles
~/.dotfiles/ubuntu/bootstrap.sh \
    --git-name "Your Name" --git-email you@example.com
exec bash -l
```

`--gpg-key KEYID` turns on commit and tag signing (see below). `--skip-apt`
skips the one step that needs sudo. `--skip-tools`, `--skip-claude`,
`--skip-configs` and `--skip-shell` narrow what runs. Every step is
idempotent, so re-running is the upgrade path.

## How it relates to `linux/`

`linux/bootstrap.sh` does four things that have nothing to do with pods: it
downloads the CLI binaries, installs the Claude config, copies the tool
configs, and writes `~/.gitconfig`. `ubuntu/bootstrap.sh` runs it with
`--skip-shell` for those, then adds what differs.

| | `linux/` (rootless pod) | `ubuntu/` (your machine) |
|---|---|---|
| System packages | none, no root | `apt`: git, curl, vim, gnupg, btop, python3 |
| CLI tools | `install-tools.sh` into `~/.local/bin` | the same script |
| Shell | `bashrc.common` + `bashrc.linux` | `bashrc.common` + `bashrc.ubuntu` |
| Services | s6, re-registered on login | systemd; nothing to do here |
| T3 Code | `--t3`: npm install, nvm shims, s6 | `t3 up`, which installs its own unit |
| Idle shutdown | tmux `keep` session | not applicable |
| ssh agent | hand-rolled, fixed socket | none; `~/.ssh/config` names the key |
| Commit signing | off, the pod holds no key | `--gpg-key` |

`bashrc.common` is the portable shell config: environment, history,
aliases, tool integrations, readline. `bashrc.ubuntu` adds `GPG_TTY` and the
per-machine `local.bash` hook, and nothing else.

## What it does not do

These are per-machine and interactive, so they stay manual.

### T3 Code and Claude Code

```sh
curl -fsSL https://claude.ai/install.sh | bash && claude auth login
curl -fsSL https://t3.codes/install.sh | sh && t3 up
```

`t3 up` sets up remote access and installs T3 Code as a systemd user
service. Update it with `t3 update`.

### GitHub over ssh

One key per machine, so a machine can be revoked without touching the others.

```sh
ssh-keygen -t ed25519 -N '' -C "$(hostname)" -f ~/.ssh/id_ed25519_github
cat >> ~/.ssh/config <<'CFG'
Host github.com
    User git
    IdentityFile ~/.ssh/id_ed25519_github
    IdentitiesOnly yes
CFG
chmod 600 ~/.ssh/config
gh auth login -p ssh -s write:gpg_key
```

`gh auth login` offers to upload the public key. The extra scope is for the
signing key in the next step.

### Signing key

```sh
gpg --batch --passphrase '' --quick-generate-key \
    "Your Name <you@example.com>" ed25519 sign never
key=$(gpg --list-secret-keys --with-colons | awk -F: '/^fpr/{print $10; exit}')
gpg --armor --export "$key" | gh gpg-key add - --title "$(hostname)"
~/.dotfiles/ubuntu/bootstrap.sh --skip-apt --skip-tools --skip-claude --gpg-key "$key"
```

The email must be a verified address on the GitHub account, or commits show
as Unverified.

The key has no passphrase on purpose. On macOS `pinentry-mac` reads the
passphrase from the Keychain, so signing never blocks. A headless Linux host
has no equivalent: a key with a passphrase stops every agent-made commit
after each reboot until someone unlocks it in a terminal. So this key relies
on disk encryption and file permissions instead, and "Verified" means the
commit was made on this machine. Give the key a passphrase with
`gpg --edit-key "$key" passwd` if the machine is interactive-only;
`bashrc.ubuntu` already exports `GPG_TTY` for the prompt.

To retire a machine, delete its ssh key and GPG key from GitHub.
