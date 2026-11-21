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
exec zsh -l
```

zsh becomes the login shell, reading the same config as the Mac. Log out and
back in for that to reach every new terminal.

`--gpg-key KEYID` turns on commit and tag signing (see below). `--skip-apt`
and `--skip-chsh` skip the two steps that need sudo. `--skip-tools`,
`--skip-claude`, `--skip-configs` and `--skip-shell` narrow what runs. Every step is
idempotent, so re-running is the upgrade path.

The Claude step replaces `~/.claude/CLAUDE.md`, `rules/`, `skills/` and
`~/.vimrc` with the versions in this repo. Only `settings.json` is backed up
first. Pass `--skip-claude` on a machine whose copies you have edited by hand.

## How it relates to `linux/`

`linux/bootstrap.sh` does four things that have nothing to do with pods: it
downloads the CLI binaries, installs the Claude config, copies the tool
configs, and writes `~/.gitconfig`. `ubuntu/bootstrap.sh` runs it with
`--skip-shell` for those, then adds what differs.

| | `linux/` (rootless pod) | `ubuntu/` (your machine) |
|---|---|---|
| System packages | none, no root | `apt`: git, curl, vim, gnupg, btop, python3, zsh, chafa, fontconfig, xz-utils |
| CLI tools | `install-tools.sh` into `~/.local/bin` | the same script |
| uv tools | none | `truefoundry`, which provides `tfy` |
| Font | none | FiraCode Nerd Font in `~/.local/share/fonts` |
| Login shell | bash | zsh, from `home/dot_zshenv` and `home/dot_config/zsh` |
| bash config | `bashrc.common` + `bashrc.linux` | `bashrc.common` + `bashrc.ubuntu` |
| yazi | not installed | config copied, plugins installed with `ya pkg install` |
| Services | s6, re-registered on login | systemd; nothing to do here |
| T3 Code | `--t3`: npm install, nvm shims, s6 | `t3 up`, which installs its own unit |
| Idle shutdown | tmux `keep` session | not applicable |
| ssh agent | hand-rolled, fixed socket | none; `~/.ssh/config` names the key |
| Commit signing | off, the pod holds no key | `--gpg-key` |

`bashrc.common` is the portable shell config: environment, history,
aliases, tool integrations, readline. `bashrc.ubuntu` adds `GPG_TTY` and the
per-machine `local.bash` hook, and nothing else. bash keeps a config because
scripts and agents still start it.

### zsh

The zsh config is the macOS one, not a copy. Its macOS-only lines are guarded
on `$OSTYPE`: `EDITOR` is `zed --wait` on macOS and `vim` elsewhere, the `ip`
alias exists only on macOS, `explorer` maps to `xdg-open`, and the `zed`
aliases fall back to `$EDITOR`. `prdiff` and the remote `update-t3` are
defined on macOS only. antidote comes from Homebrew on macOS and from a
clone at `~/.config/zsh/.antidote` here. Per-machine settings go in
`~/.config/zsh/local.zsh`.

The FiraCode Nerd Font is installed for terminals that run on this machine.
A terminal you connect from draws the prompt with its own fonts, so it needs
a Nerd Font too.

### What is left out of the Brewfile

`mpv` and Wireshark (desktop apps, and `mpv` pulls in a large dependency
tree), the GUI casks, `pinentry-mac`, `proxytunnel`, and `node` with
`hunkdiff`, which only `prdiff` used.

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
email=you@example.com
gpg --batch --passphrase '' --quick-generate-key \
    "Your Name <$email>" ed25519 sign never
key=$(gpg --list-secret-keys --with-colons "$email" | awk -F: '/^fpr/{print $10; exit}')
gpg --armor --export "$key" | gh gpg-key add - --title "$(hostname)"
~/.dotfiles/ubuntu/bootstrap.sh --skip-apt --skip-tools --skip-claude --gpg-key "$key"
```

Check it with a throwaway commit. It should sign without prompting:

```sh
d=$(mktemp -d) && git -C "$d" init -q \
    && git -C "$d" commit -q --allow-empty -m "test: Check signing" \
    && git -C "$d" log --show-signature -1
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
