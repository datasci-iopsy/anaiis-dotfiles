#!/usr/bin/env bash
# install-dbt-skills.sh
# Vendors a curated subset of dbt-labs/dbt-agent-skills into ~/.dotfiles/claude/skills/.
#
# For each skill in SKILLS:
#   - Copies upstream SKILL.md and applies a uniform three-key frontmatter patch:
#       name:           prefixed with "dbt-"
#       user-invocable: forced to "true"
#       description:    upstream text preserved; soft-gate sentence appended
#   - Symlinks any sibling files/dirs next to SKILL.md (resources, templates, etc.)
#
# Idempotent: safe to re-run after a submodule update.
# To remove a skill, delete it from SKILLS and re-run.

set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VENDOR="$DOTFILES/vendor/dbt-agent-skills/skills/dbt/skills"
DEST="$DOTFILES/claude/skills"

# Allow-list: add or remove upstream skill folder names here.
SKILLS=(
	using-dbt-for-analytics-engineering
	running-dbt-commands
	adding-dbt-unit-test
	building-dbt-semantic-layer
	answering-natural-language-questions-with-dbt
	fetching-dbt-docs
)

GATE_SUFFIX="Auto-triggers only when dbt_project.yml is present in the working tree or a parent directory; otherwise invoke explicitly via /dbt-<name>."

patch_skill_md() {
	local src="$1"
	local dst="$2"
	local skill_name="$3"

	# Split upstream SKILL.md into frontmatter and body.
	# Frontmatter is between the first and second "---" lines.
	local in_front=0 front="" body=""
	local front_done=0 delim_count=0
	while IFS= read -r line || [[ -n "$line" ]]; do
		if [[ "$line" == "---" ]]; then
			delim_count=$((delim_count + 1))
			if [[ $delim_count -eq 1 ]]; then
				in_front=1
				continue
			elif [[ $delim_count -eq 2 ]]; then
				in_front=0
				front_done=1
				continue
			fi
		fi
		if [[ $in_front -eq 1 ]]; then
			front+="$line"$'\n'
		elif [[ $front_done -eq 1 ]]; then
			body+="$line"$'\n'
		fi
	done <"$src"

	# Apply three-key patch to frontmatter lines.
	local new_front="" desc_found=0 desc_buf="" in_desc_block=0
	while IFS= read -r line || [[ -n "$line" ]]; do
		# Patch: name
		if [[ "$line" =~ ^name:[[:space:]] ]]; then
			new_front+="name: dbt-${skill_name}"$'\n'
			continue
		fi
		# Patch: user-invocable
		if [[ "$line" =~ ^user-invocable:[[:space:]] ]]; then
			new_front+="user-invocable: true"$'\n'
			continue
		fi
		# Patch: description (may be single-line or block scalar)
		if [[ "$line" =~ ^description:[[:space:]] ]]; then
			desc_found=1
			local rest="${line#description: }"
			# Check for block scalar marker ("|" or ">")
			if [[ "$rest" == "|"* ]] || [[ "$rest" == ">"* ]]; then
				# Block scalar: collect indented continuation lines, then append suffix
				in_desc_block=1
				desc_buf="description: $rest"$'\n'
				continue
			else
				# Single-line description: append suffix inline
				new_front+="description: ${rest} ${GATE_SUFFIX}"$'\n'
				continue
			fi
		fi
		# While collecting a block-scalar description, accumulate indented lines
		if [[ $in_desc_block -eq 1 ]]; then
			if [[ "$line" =~ ^[[:space:]] ]] || [[ -z "$line" ]]; then
				desc_buf+="$line"$'\n'
				continue
			else
				# First non-indented line ends the block; strip trailing newline and append suffix
				desc_buf="${desc_buf%$'\n'}"
				new_front+="${desc_buf}"$'\n'
				new_front+="  ${GATE_SUFFIX}"$'\n'
				in_desc_block=0
				desc_buf=""
				new_front+="$line"$'\n'
				continue
			fi
		fi
		new_front+="$line"$'\n'
	done <<<"$front"

	# If block description never closed (EOF), flush it
	if [[ $in_desc_block -eq 1 ]]; then
		desc_buf="${desc_buf%$'\n'}"
		new_front+="${desc_buf}"$'\n'
		new_front+="  ${GATE_SUFFIX}"$'\n'
	fi

	# Write patched SKILL.md
	{
		printf -- '---\n'
		printf '%s' "$new_front"
		printf -- '---\n'
		printf '%s' "$body"
	} >"$dst"
}

echo "=== dbt skills: installing ${#SKILLS[@]} skills ==="
echo ""

# Track which dbt-* dirs are current so we can prune removed ones.
current_names=()

for skill in "${SKILLS[@]}"; do
	src_dir="$VENDOR/$skill"
	dst_dir="$DEST/dbt-$skill"
	current_names+=("dbt-$skill")

	if [[ ! -d "$src_dir" ]]; then
		echo "  WARN $skill not found in submodule at $src_dir -- skipping"
		continue
	fi

	mkdir -p "$dst_dir"

	# Patch SKILL.md (copy + mutate frontmatter)
	patch_skill_md "$src_dir/SKILL.md" "$dst_dir/SKILL.md" "$skill"
	echo "  patch  $dst_dir/SKILL.md"

	# Symlink sibling assets (anything that is not SKILL.md)
	for item in "$src_dir"/*; do
		base="$(basename "$item")"
		[[ "$base" == "SKILL.md" ]] && continue
		if [[ -L "$dst_dir/$base" ]] && [[ "$(readlink "$dst_dir/$base")" == "$item" ]]; then
			echo "  ok     $dst_dir/$base"
		else
			ln -sf "$item" "$dst_dir/$base"
			echo "  link   $dst_dir/$base -> $item"
		fi
	done
done

# Prune dbt-* dirs that are no longer in the allow-list
for existing in "$DEST"/dbt-*/; do
	[[ -d "$existing" ]] || continue
	base="$(basename "$existing")"
	found=0
	for name in "${current_names[@]}"; do
		[[ "$name" == "$base" ]] && found=1 && break
	done
	if [[ $found -eq 0 ]]; then
		rm -rf "$existing"
		echo "  prune  $existing (removed from allow-list)"
	fi
done

echo ""
echo "Done. Run 'git submodule status' to verify submodule pin."
