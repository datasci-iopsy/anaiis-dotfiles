#!/usr/bin/env bash
# bootstrap-doctor.sh -- read-only check that this machine is wired for the dotfiles repo.
#
# Usage: bash ~/.claude/scripts/bootstrap-doctor.sh
#
# Prints `ok <what>` or `MISSING <what>: <fix command>` for each check, then `doctor: <n> missing`.
# A `WARN <what>: <fix command>` line reports a gap that does not count in n.
# Exits 1 when n is above 0. The script writes nothing: it only reads files and runs read-only
# commands, so it is safe to run at any time.
#
# Checks:
#   1. ~/.bashrc exists and holds the PATH line and the shared.bash source line
#   2. the login shell file (the first of ~/.bash_profile, ~/.bash_login, ~/.profile) mentions ~/.bashrc
#   3. each ~/.claude link resolves to its own target in ~/anaiis-dotfiles/claude/, and
#      ~/.claude/memory is a local folder (WARN when it is absent or still a link)
#
# In checks 1 and 2 a line that starts with # does not count: the shell never reads it.
# In check 2 the name must end at .bashrc: a line that sources only .bashrc.local does not count.
#   4. each enabled plugin has a folder in ~/.claude/plugins/cache/
#   5. when gh uses the ssh protocol, known_hosts holds a github.com key
#   6. when claude is on PATH, its version is at least 2.1.295 (onFailure support for PreToolUse guards)
#   7. settings.json pins env.CLAUDE_CODE_SHELL to an executable bash whose major version is in
#      APPROVED_BASH_MAJORS, and every command in it starts with ${CLAUDE_CODE_SHELL:-bash}
#
# Tools used: dirname basename readlink grep jq gh ssh-keygen claude, and the pinned bash (check 7,
# by absolute path, run once with -c to print its major). ssh-keygen reads the passwd
# home and ignores $HOME, so its call passes -f.

# shellcheck disable=SC2088 # "~" is literal text in the messages, never a path to expand
set -u

MISSING=0
# The Homebrew bash majors that the harness is approved to run on. Check 7 fails for any other major,
# older or newer. To approve a new major, edit this one line (for example "5 6"). The suites read it.
APPROVED_BASH_MAJORS="5"
ok() { printf 'ok %s\n' "$1"; }
missing() {
	printf 'MISSING %s: %s\n' "$1" "$2"
	MISSING=$((MISSING + 1))
}
warn() { printf 'WARN %s: %s\n' "$1" "$2"; }

FIX_BASHRC='bash ~/anaiis-dotfiles/install.sh --bashrc-only'
FIX_LINKS='bash ~/anaiis-dotfiles/install.sh --symlinks-only'
FIX_KEYS='bash ~/anaiis-dotfiles/install.sh --hostkeys-only'
# shellcheck disable=SC2016 # $HOME stays literal: the user pastes this line into a file
FIX_LOGIN='add this line to it: [ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"'
FIX_PLUGIN='start Claude Code once, run /reload-plugins, and read the /plugin Errors tab. A GitHub clone over SSH needs the host key from the github.com check (fix: bash ~/anaiis-dotfiles/install.sh --hostkeys-only).'
FIX_PIN='set env.CLAUDE_CODE_SHELL in ~/anaiis-dotfiles/claude/settings.json to the Homebrew bash path, for example /opt/homebrew/bin/bash'
FIX_MAJOR='install an approved bash (brew install bash), or approve this major by editing APPROVED_BASH_MAJORS in ~/anaiis-dotfiles/claude/scripts/bootstrap-doctor.sh'
# shellcheck disable=SC2016 # ${...} stays literal: the user pastes this text into settings.json
FIX_PREFIX='start each command in ~/anaiis-dotfiles/claude/settings.json with ${CLAUDE_CODE_SHELL:-bash} (a bare bash follows PATH)'

# phys <path>: print the physical path of an existing path, with every link resolved.
phys() {
	local p="$1" t d
	while [ -L "$p" ]; do
		t="$(readlink "$p")"
		case "$t" in
			/*) p="$t" ;;
			*) p="$(dirname "$p")/$t" ;;
		esac
	done
	d="$(cd "$(dirname "$p")" 2>/dev/null && pwd -P)" || return 1
	printf '%s/%s\n' "$d" "$(basename "$p")"
}

# active <file> <regex>: succeed when a line holds the pattern and its first character other than
# a space or a tab is not #. A line that ends in a comment still counts.
active() {
	grep -qE "^[[:space:]]*([^[:space:]#].*)?$2" "$1"
}

# ---- 1. ~/.bashrc -----------------------------------------------------------
if [ ! -f "$HOME/.bashrc" ]; then
	missing "~/.bashrc (absent)" "$FIX_BASHRC"
else
	if active "$HOME/.bashrc" 'anaiis-dotfiles/bin'; then
		ok "~/.bashrc PATH line"
	else
		missing "~/.bashrc PATH line" "$FIX_BASHRC"
	fi
	if active "$HOME/.bashrc" 'anaiis-dotfiles/bash/shared[.]bash'; then
		ok "~/.bashrc shared.bash line"
	else
		missing "~/.bashrc shared.bash line" "$FIX_BASHRC"
	fi
fi

# ---- 2. login shell file ----------------------------------------------------
# bash reads only the first of these files, so only that file can load ~/.bashrc.
login=""
for f in .bash_profile .bash_login .profile; do
	if [ -f "$HOME/$f" ]; then
		login="$f"
		break
	fi
done
if [ -z "$login" ]; then
	missing "login shell file (no ~/.bash_profile, ~/.bash_login, or ~/.profile)" "$FIX_BASHRC"
elif active "$HOME/$login" '[.]bashrc([^[:alnum:]_.-]|$)'; then
	ok "~/$login mentions ~/.bashrc"
else
	missing "~/$login (never mentions ~/.bashrc)" "$FIX_LOGIN"
fi

# ---- 3. ~/.claude links -----------------------------------------------------
root=""
[ -e "$HOME/anaiis-dotfiles/claude" ] && root="$(phys "$HOME/anaiis-dotfiles/claude")"
for name in settings.json keybindings.json rules commands skills agents hooks scripts; do
	link="$HOME/.claude/$name"
	if [ ! -L "$link" ]; then
		if [ -e "$link" ]; then why="not a link"; else why="absent"; fi
	elif [ ! -e "$link" ]; then
		why="dangling"
	else
		why="points outside ~/anaiis-dotfiles/claude"
		resolved="$(phys "$link")"
		if [ -n "$root" ]; then
			case "$resolved" in
				"$root/$name") why="" ;;
				"$root"/*) why="points to the wrong place, expected ~/anaiis-dotfiles/claude/$name" ;;
			esac
		fi
	fi
	if [ -z "$why" ]; then
		ok "~/.claude/$name -> ~/anaiis-dotfiles/claude"
	else
		missing "~/.claude/$name ($why)" "$FIX_LINKS"
	fi
done
# ~/.claude/memory is a local folder, not a link into the repo. A new machine has no memory yet, so
# an absent folder is a WARN, not a gap. A link is the old layout that install.sh converts.
if [ -L "$HOME/.claude/memory" ]; then
	warn "~/.claude/memory (a link, not a local folder)" "$FIX_LINKS"
elif [ -d "$HOME/.claude/memory" ]; then
	ok "~/.claude/memory (local folder)"
else
	warn "~/.claude/memory (absent)" "$FIX_LINKS"
fi

# ---- 4. plugins -------------------------------------------------------------
settings="$HOME/.claude/settings.json"
if ! command -v jq >/dev/null 2>&1; then
	missing "jq (needed to read the plugin list)" "brew install jq"
elif [ ! -f "$settings" ]; then
	missing "plugin list (~/.claude/settings.json absent)" "$FIX_LINKS"
elif ! plugins="$(jq -r '(.enabledPlugins // {}) | to_entries[] | select(.value == true) | .key' "$settings" 2>/dev/null)"; then
	missing "plugin list (~/.claude/settings.json is not valid JSON)" "repair the file, then run this script again"
elif [ -z "$plugins" ]; then
	ok "plugins (none enabled)"
else
	while IFS= read -r key; do
		if [ -d "$HOME/.claude/plugins/cache/${key##*@}/${key%@*}" ]; then
			ok "plugin $key"
		else
			missing "plugin $key" "$FIX_PLUGIN"
		fi
	done <<EOF
$plugins
EOF
fi

# ---- 5. GitHub host key -----------------------------------------------------
if ! command -v gh >/dev/null 2>&1; then
	ok "github.com host key (not needed: gh not found)"
else
	proto="$(gh config get git_protocol 2>/dev/null)" || proto=""
	if [ "$proto" != "ssh" ]; then
		ok "github.com host key (not needed: gh protocol is ${proto:-unset})"
	elif ssh-keygen -F github.com -f "$HOME/.ssh/known_hosts" >/dev/null 2>&1; then
		ok "github.com host key"
	else
		missing "github.com host key (~/.ssh/known_hosts)" "$FIX_KEYS"
	fi
fi

# ---- 6. Claude Code version -------------------------------------------------
# Claude Code reads AGENTS.md from 2.1.277, and supports onFailure for PreToolUse hooks from
# 2.1.295. Without onFailure, a guard that cannot start is a non-blocking error, so the doctor
# checks the higher minimum.

# ver_ge <a> <b>: succeed when version a is at least version b. Each is major.minor.patch, digits
# only. Any other text for a fails. The parts compare as integers, so 2.1.1000 is above 2.1.295.
ver_ge() {
	local a1 a2 a3 ax b1 b2 b3 part
	IFS=. read -r a1 a2 a3 ax <<EOF
$1
EOF
	IFS=. read -r b1 b2 b3 <<EOF
$2
EOF
	for part in "$a1" "$a2" "$a3"; do
		case "$part" in
			'' | *[!0-9]*) return 1 ;;
		esac
	done
	[ -z "$ax" ] || return 1
	[ "$a1" -gt "$b1" ] && return 0
	[ "$a1" -lt "$b1" ] && return 1
	[ "$a2" -gt "$b2" ] && return 0
	[ "$a2" -lt "$b2" ] && return 1
	[ "$a3" -ge "$b3" ]
}

if ! command -v claude >/dev/null 2>&1; then
	ok "claude version (not needed: claude not found)"
else
	# The first word of the first line: "2.1.318 (Claude Code)" gives 2.1.318.
	cv="$(claude --version 2>/dev/null)" || cv=""
	cv="${cv%%$'\n'*}"
	cv="${cv%% *}"
	if ver_ge "$cv" 2.1.295; then
		ok "claude version $cv"
	else
		missing "claude version" "update Claude Code"
	fi
fi

# ---- 7. harness bash --------------------------------------------------------
# The harness runs on one approved Homebrew bash major. settings.json pins the shell of the Bash tool
# with env.CLAUDE_CODE_SHELL, and every command starts with ${CLAUDE_CODE_SHELL:-bash}, so one pin
# controls the Bash tool and the hooks. Without a readable settings.json, check 4 already reports the
# cause, so this check adds no line. The pin runs once, with -c, to print its own major version.
if command -v jq >/dev/null 2>&1 && [ -f "$settings" ] && jq -e . "$settings" >/dev/null 2>&1; then
	pin="$(jq -r '.env.CLAUDE_CODE_SHELL // empty' "$settings")"
	if [ -z "$pin" ]; then
		missing "harness bash pin (env.CLAUDE_CODE_SHELL absent in ~/.claude/settings.json)" "$FIX_PIN"
	elif [ ! -f "$pin" ] || [ ! -x "$pin" ]; then
		missing "harness bash pin ($pin is not an executable file)" "$FIX_PIN"
	else
		# shellcheck disable=SC2016 # the pinned bash expands ${BASH_VERSINFO[0]}, not this shell
		major="$("$pin" -c 'printf %s "${BASH_VERSINFO[0]}"' 2>/dev/null)" || major=""
		approved=no
		for m in $APPROVED_BASH_MAJORS; do
			[ "$major" = "$m" ] && approved=yes
		done
		if [ "$approved" = yes ]; then
			ok "harness bash $pin (major $major)"
		else
			missing "harness bash $pin (major ${major:-unknown}, approved: $APPROVED_BASH_MAJORS)" "$FIX_MAJOR"
		fi
	fi
	# shellcheck disable=SC2016 # ${...} stays literal: it is the text that settings.json holds
	counts="$(jq -r '[.. | objects | select(has("command")) | .command | strings] | "\(length) \(map(select(startswith("${CLAUDE_CODE_SHELL:-bash} ") | not)) | length)"' "$settings")"
	total="${counts% *}"
	bare="${counts#* }"
	if [ "$bare" -eq 0 ]; then
		ok "hook commands start with the pin prefix ($total)"
	else
		missing "hook commands without the pin prefix ($bare of $total)" "$FIX_PREFIX"
	fi
fi

printf 'doctor: %s missing\n' "$MISSING"
[ "$MISSING" -eq 0 ]
