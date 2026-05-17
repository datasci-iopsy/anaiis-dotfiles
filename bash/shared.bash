# ~/anaiis-dotfiles/bash/shared.bash
#
# Tracked personal shell preferences, sourced by ~/.bashrc.local.
# Edit here to keep both machines in sync via git pull.
# Machine-local overrides (GCP project, API keys) stay in ~/.bashrc.local.

# ── OS detection ──────────────────────────────────────────────────────────────
_os="$(uname -s)"

# ── macOS-only ────────────────────────────────────────────────────────────────
if [ "$_os" = "Darwin" ]; then
	export BASH_SILENCE_DEPRECATION_WARNING=1
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

# ── bash-completion ───────────────────────────────────────────────────────────
if [ -r "$(brew --prefix 2>/dev/null)/etc/profile.d/bash_completion.sh" ]; then
	. "$(brew --prefix)/etc/profile.d/bash_completion.sh"
fi

# ── pyenv ─────────────────────────────────────────────────────────────────────
if [ -d "$HOME/.pyenv" ]; then
	export PYENV_ROOT="$HOME/.pyenv"
	export PATH="$PYENV_ROOT/bin:$PATH"
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
