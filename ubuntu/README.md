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

The Claude step replaces `~/.claude/CLAUDE.md`, `rules/`, each skill in this
repo and `~/.vimrc` with the versions here. It deletes `claude-review`,
`codex-review`, `unslop` and `using-cmux` from `~/.claude/skills/` instead,
because a Claude plugin supplies the first three on Linux and cmux is
macOS-only (see [`linux/`](../linux/README.md#skills-left-to-a-plugin)).
Only `settings.json` is backed up first. Pass `--skip-claude` on a machine
whose copies you have edited by hand.

## How it relates to `linux/`

`linux/bootstrap.sh` does four things that have nothing to do with pods: it
downloads the CLI binaries, installs the Claude config, copies the tool
configs, and writes `~/.gitconfig`. `ubuntu/bootstrap.sh` runs it with
`--skip-shell` for those, then adds what differs.

| | `linux/` (rootless pod) | `ubuntu/` (your machine) |
|---|---|---|
| System packages | none, no root | `apt`: git, curl, vim, gnupg, btop, python3, zsh, chafa, fontconfig, xz-utils, podman, uidmap, passt; docker-compose-v2 without recommends |
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
| Containers | none, a pod cannot run them unprivileged | rootless Podman, socket-activated Docker API |

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

### Containers

Podman, rootless. It has no daemon: a container is a child process of your
user, so when the last container stops its memory is back. What stays is
`catatonit`, a pause process of under a megabyte that holds the user
namespace open. Docker Engine keeps `dockerd` and `containerd` resident
whether or not anything runs, and they run as root.

Tools that speak the Docker API (`docker-compose`, lazydocker,
testcontainers) reach Podman through `podman.socket`. systemd holds the
socket and starts `podman system service` on the first connection; the
service exits after 5 idle seconds. `DOCKER_HOST` points at it from
`~/.zshenv` and `bashrc.ubuntu` unless `DOCKER_HOST` or `DOCKER_CONTEXT` is
already set, and `docker` is an alias for `podman` wherever Docker itself is
absent.

`podman compose` runs `docker-compose`. Ubuntu's `docker-compose-v2` package
provides it, installed on its own with `--no-install-recommends`: it
recommends `docker.io`, so a default install would bring the Docker daemon
along. The package puts the binary only at the Docker CLI plugin path, so
the bootstrap links it into `~/.local/bin`.

The one Podman setting, silencing the notice `podman compose` prints before
every call, is a drop-in at
`~/.config/containers/containers.conf.d/compose.conf`, so per-user settings
in `containers.conf` survive a re-run.

Two habits matter on a shared host:

- A port published as `-p 27017:27017` binds every interface, and Podman has
  no setting that changes that default. Publish on loopback, `-p
  127.0.0.1:27017:27017`, and write `127.0.0.1:` into every compose `ports`
  entry. A service only other containers talk to needs no `ports` at all.
- Give heavy services a memory limit (`--memory`, or `mem_limit` in
  compose). A container runs in its own `libpod-*.scope` under the user
  manager's `user.slice`, not in the cgroup of the shell that started it, so
  a limit on that shell's slice does not reach it.

Nothing restarts containers after a reboot. `--restart=always` needs
`podman-restart.service`, which is deliberately not enabled: these are
throwaway dev services.

Avoid `podman system migrate` as a cleanup step. It stops every container of
the user, including ones another session is using.

#### AppArmor and compose teardown

Ubuntu 26.04's `pasta` AppArmor profile (passt `0.0~git20260120`) does not
let `pasta` receive signals from the `podman` profile. Networks Podman
creates, which every compose project gets, run behind one shared `pasta`
process that Podman stops with SIGTERM when the last container leaves. The
kernel denies it, so the first `docker-compose down` or `podman compose
down` fails with `rootless netns: kill network process: permission denied`
and leaves a stopped container behind. A second `down` removes it.
Containers on the default network are not affected.

The fix is one rule in the profile, letting `pasta` receive SIGTERM, the
only signal Podman's teardown sends, from the `podman` profile. An upstream
passt patch from June 2026 adds the same grant. The profile has no `local/`
include, so this edits a conffile. The checksum guard limits the edit to the
packaged file and stops a second insertion on a re-run. dpkg keeps the edit
while the packaged profile is unchanged, and asks before replacing it.

```sh
profile=/etc/apparmor.d/usr.bin.pasta
printf '%s  %s\n' c7b2926613394e4de6f5f146a87d0b63 "$profile" | md5sum --check --status &&
  sudo sed -i '/^  include <abstractions\/pasta>$/a\  signal (receive) set=(term) peer=podman,' "$profile" &&
  sudo apparmor_parser -r "$profile"
```

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
