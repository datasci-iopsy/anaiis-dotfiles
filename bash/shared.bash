# ~/anaiis-dotfiles/bash/shared.bash
#
# Tracked personal shell preferences, sourced by ~/.bashrc.
# Edit here to keep both machines in sync via git pull.
# Machine-local overrides (GCP project, API keys) stay in ~/.bashrc.local.

# ── OS detection ──────────────────────────────────────────────────────────────
_os="$(uname -s)"

# ── macOS-only ────────────────────────────────────────────────────────────────
if [ "$_os" = "Darwin" ]; then
	export BASH_SILENCE_DEPRECATION_WARNING=1
	export CLICOLOR=1
	export LSCOLORS=GxFxCxDxBxegedabagaced
fi

# ── Homebrew ──────────────────────────────────────────────────────────────────
# macOS: Apple Silicon (/opt/homebrew) and Intel (/usr/local)
# Linux: Linuxbrew user install (~/.linuxbrew) and system install (/home/linuxbrew/.linuxbrew)
for _brew_prefix in \
	/opt/homebrew \
	/usr/local \
	"$HOME/.linuxbrew" \
	/home/linuxbrew/.linuxbrew; do
	if [ -x "${_brew_prefix}/bin/brew" ]; then
		eval "$("${_brew_prefix}/bin/brew" shellenv)"
		break
	fi
done
unset _brew_prefix

# Warn when installed packages diverge from Brewfile (once per day, non-blocking)
_brewfile="$HOME/anaiis-dotfiles/Brewfile"
_bfstamp="${XDG_CACHE_HOME:-$HOME/.cache}/brewfile-check.stamp"
if command -v brew &>/dev/null && [ -f "$_brewfile" ]; then
	_bfage=$(($(date +%s) - $(stat -f %m "$_bfstamp" 2>/dev/null || echo 0)))
	if [ ! -f "$_bfstamp" ] || [ "$_bfage" -gt 86400 ]; then
		touch "$_bfstamp"
		(brew bundle check --file="$_brewfile" &>/dev/null \
			|| echo "[dotfiles] Brewfile out of sync. Run: brew bundle --file=$_brewfile") &
	fi
fi
unset _brewfile _bfstamp _bfage

# ── bash-completion ───────────────────────────────────────────────────────────
if [ -r "$(brew --prefix 2>/dev/null)/etc/profile.d/bash_completion.sh" ]; then
	. "$(brew --prefix)/etc/profile.d/bash_completion.sh"
fi

# ── pyenv ─────────────────────────────────────────────────────────────────────
if [ -d "$HOME/.pyenv" ]; then
	export PYENV_ROOT="$HOME/.pyenv"
	export PATH="$PYENV_ROOT/bin:$PATH"
	eval "$(pyenv init -)"
	eval "$(pyenv virtualenv-init -)" 2>/dev/null
fi

# ── pipx / uv tools ───────────────────────────────────────────────────────────
[ -d "$HOME/.local/bin" ] && export PATH="$PATH:$HOME/.local/bin"

# ── Google Cloud SDK ──────────────────────────────────────────────────────────
if [ -f "$HOME/google-cloud-sdk/path.bash.inc" ]; then
	. "$HOME/google-cloud-sdk/path.bash.inc"
fi
if [ -f "$HOME/google-cloud-sdk/completion.bash.inc" ]; then
	. "$HOME/google-cloud-sdk/completion.bash.inc"
fi

# ── direnv ────────────────────────────────────────────────────────────────────
if command -v direnv >/dev/null 2>&1; then
	eval "$(direnv hook bash)"
fi

# ── thefuck ───────────────────────────────────────────────────────────────────
if command -v thefuck >/dev/null 2>&1; then
	eval "$(thefuck --alias)"
	eval "$(thefuck --alias FUCK)"
fi

# ── Claude Code defaults (override in ~/.bashrc.local per machine) ────────────
# Plain export so re-sourcing shared.bash always picks up changed defaults.
# ~/.bashrc.local is sourced AFTER this file by ~/.bashrc, so any var set
# there wins over these values automatically.
# Model selection; overrides settings.json "model". Use /model or --model for
# one-off changes; this is the baseline. Pins each class to a specific snapshot
# so /model picks resolve deterministically across machines.
export ANTHROPIC_MODEL="claude-opus-4-7"
export ANTHROPIC_DEFAULT_OPUS_MODEL="claude-opus-4-7"
export ANTHROPIC_DEFAULT_SONNET_MODEL="claude-sonnet-4-6"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="claude-haiku-4-5-20251001"

# Effort and output sizing; overrides settings.json "effortLevel".
export CLAUDE_CODE_EFFORT_LEVEL="medium"
export CLAUDE_CODE_MAX_OUTPUT_TOKENS="16000"

# Bash and API timeouts. Research workflows can hit long-running R or DuckDB
# commands; raise BASH_MAX_TIMEOUT_MS in ~/.bashrc.local if needed.
export BASH_DEFAULT_TIMEOUT_MS="120000"
export BASH_MAX_TIMEOUT_MS="600000"
export API_TIMEOUT_MS="600000"

# Hygiene: one switch disables auto-updater, feedback prompts, error reporting,
# and telemetry. Comment out in ~/.bashrc.local if OTel is wanted.
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="1"

# ── Prompt, hostname, directory, git branch ──────────────────────────────────
git_branch() {
	local dir_name branch_name
	dir_name=$(basename "$(pwd)")
	if git rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
		branch_name=$(git symbolic-ref --short -q HEAD)
		PS1="\[\e[1;32m\]\h\e[0m\]:\[\e[1;34m\][${dir_name}]\[\e[0m\]:\[\e[1;33m\]{${branch_name}}\[\e[0m\] "
	else
		PS1="\[\e[1;32m\]\h\e[0m\]:\[\e[1;34m\][${dir_name}]\[\e[0m\] "
	fi
}
PROMPT_COMMAND=git_branch

# ── ls aliases ────────────────────────────────────────────────────────────────
if [ "$_os" = "Darwin" ]; then
	alias ls='ls -GFhp'
	alias ll='ls -lAGFhp'
	alias lt='ls -lAGFhtr'
	alias l.='ls -dAGFhp .* 2>/dev/null'
else
	alias ls='ls --color=auto -Fhp'
	alias ll='ls --color=auto -lAFhp'
	alias lt='ls --color=auto -lAFhtr'
	alias l.='ls --color=auto -dAFhp .* 2>/dev/null'
fi
unset _os

# ── Navigation ────────────────────────────────────────────────────────────────
alias ~='cd ~'
alias cd..='cd ../'
alias ..='cd ../'
alias ...='cd ../../'
alias .3='cd ../../../'
alias .4='cd ../../../../'
alias .5='cd ../../../../../'
alias .6='cd ../../../../../../'
alias cp='cp -iv'
alias mv='mv -iv'
alias mkdir='mkdir -pv'
alias rsync='rsync -hvrP'
alias pwd='pwd -P'
alias du='du -sh'
alias c='clear'
alias bashconfig='vim ~/.bashrc'
alias bashsrc='source ~/.bashrc'

# ── Git ───────────────────────────────────────────────────────────────────────
alias gst='git status'
alias gco='git checkout'
alias gcam='git commit -a'
alias gl='git pull --rebase'
alias gp='git push'
alias gd='git diff'
alias grb='git rebase'
alias gcp='git cherry-pick'
alias gsta='git stash push'
alias gstl='git stash list'
alias gaa='git add --all'
alias grh='git reset --hard'
alias gclean='git clean -fd'
alias glog="git log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset'"

# ── Python ────────────────────────────────────────────────────────────────────
alias wipe_pip='pip freeze | cut -d "@" -f1 | xargs pip uninstall -y'

# ── Google Cloud ──────────────────────────────────────────────────────────────
alias gc-update='gcloud components update'
alias gc-auth='gcloud auth login; gcloud auth application-default login'
alias gc-authList='gcloud auth list'

# ── Claude ────────────────────────────────────────────────────────────────────
alias claude-fast='claude --permission-mode bypassPermissions'

# ── CodeRabbit ────────────────────────────────────────────────────────────────
alias cr='coderabbit'
alias cr-status='coderabbit auth status'
cr-login() {
	if [ -z "$CODERABBIT_API_KEY" ]; then
		echo "cr-login: CODERABBIT_API_KEY is not set in ~/.bashrc.local" >&2
		return 1
	fi
	if [ -z "$CODERABBIT_ORG_ID" ]; then
		echo "cr-login: CODERABBIT_ORG_ID is not set in ~/.bashrc.local" >&2
		return 1
	fi
	if ! command -v jq >/dev/null 2>&1; then
		echo "cr-login: jq is required but not installed" >&2
		return 1
	fi
	if ! coderabbit auth login --api-key "$CODERABBIT_API_KEY"; then
		echo "cr-login: API key authentication failed" >&2
		return 1
	fi
	local cfg
	if [ -d "$HOME/Library/Application Support/coderabbit" ]; then
		cfg="$HOME/Library/Application Support/coderabbit/user-data.json"
	else
		cfg="${XDG_CONFIG_HOME:-$HOME/.config}/coderabbit/user-data.json"
	fi
	if [ ! -f "$cfg" ]; then
		echo "cr-login: config file not found at $cfg" >&2
		return 1
	fi
	if ! jq --arg id "$CODERABBIT_ORG_ID" '.orgId = $id' "$cfg" >"$cfg.tmp"; then
		echo "cr-login: failed to update orgId in $cfg" >&2
		rm -f "$cfg.tmp"
		return 1
	fi
	mv "$cfg.tmp" "$cfg"
	echo "cr-login: authenticated and org set"
}

# ── Shell functions ───────────────────────────────────────────────────────────
mcd() { mkdir -p "$1" && cd "$1"; }
