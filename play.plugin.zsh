#!/usr/bin/env zsh
# ─────────────────────────────────────────────────────────────────
# zsh-play — lightweight playground workspace manager for zsh
# https://github.com/ivanleomk/zsh-play
# ─────────────────────────────────────────────────────────────────

# Configuration (override these in .zshrc BEFORE sourcing this plugin)
: ${PLAY_DIR:="$HOME/agy-playgrounds"}       # where playgrounds live
: ${PLAY_OPEN_CMD:="agy --new-window"}   # command to open a playground (e.g. agy, code, cursor, zed)
: ${PLAY_AG_WS_STORAGE:="$HOME/Library/Application Support/Antigravity/User/workspaceStorage"}
_PLAY_PLUGIN_DIR="${0:A:h}"

play() {
  local base="$PLAY_DIR"

  # ── helpers ──────────────────────────────────────────────────
  local _play_help() {
    cat <<EOF
🎮 play — playground workspace manager

Usage:
  play [name]            Create & open a playground (default: timestamped)
  play ls                List playgrounds & recent Antigravity workspaces
  play rm [name]         Trash a playground (interactive picker if no name)
  play rm --all          Trash all playgrounds
  play rm --purge <name> Permanently delete (no recovery)
  play help              Show this help

Options:
  -f, --force            Skip confirmation prompts
  --purge                Permanent delete instead of trash

Examples:
  play                   → $base/20260324-221500/
  play research          → $base/research/
  play ls                → list playgrounds + Antigravity workspaces
  play rm aws            → trash 'aws' (recoverable)
  play rm                → pick from list interactively
  play rm --purge aws    → permanently delete 'aws'

Configuration (set in .zshrc before sourcing):
  PLAY_DIR               Playground directory (default: ~/agy-playgrounds)
  PLAY_OPEN_CMD          Editor command (default: code)
  PLAY_AG_WS_STORAGE     Antigravity workspace storage path (auto-detected)

Playgrounds are stored in $base/
Trashed items go to macOS Trash (recoverable via Finder).
EOF
  }

  # human-readable size for a directory
  local _play_size() {
    du -sh "$1" 2>/dev/null | cut -f1 | sed 's/^ *//'
  }

  # relative age string from a directory's modification time
  local _play_age() {
    local mod_epoch now_epoch diff
    mod_epoch=$(stat -f '%m' "$1" 2>/dev/null) || return
    now_epoch=$(date +%s)
    diff=$(( now_epoch - mod_epoch ))

    if   (( diff < 60 ));    then echo "just now"
    elif (( diff < 3600 ));  then echo "$(( diff / 60 ))m ago"
    elif (( diff < 86400 )); then echo "$(( diff / 3600 ))h ago"
    elif (( diff < 604800 )); then
      local days=$(( diff / 86400 ))
      (( days == 1 )) && echo "1 day ago" || echo "${days} days ago"
    elif (( diff < 2592000 )); then
      local weeks=$(( diff / 604800 ))
      (( weeks == 1 )) && echo "1 week ago" || echo "${weeks} weeks ago"
    else
      local months=$(( diff / 2592000 ))
      (( months == 1 )) && echo "1 month ago" || echo "${months} months ago"
    fi
  }

  # relative age string from an epoch timestamp
  local _play_age_epoch() {
    local mod_epoch="$1" now_epoch diff
    now_epoch=$(date +%s)
    diff=$(( now_epoch - mod_epoch ))

    if   (( diff < 60 ));    then echo "just now"
    elif (( diff < 3600 ));  then echo "$(( diff / 60 ))m ago"
    elif (( diff < 86400 )); then echo "$(( diff / 3600 ))h ago"
    elif (( diff < 604800 )); then
      local days=$(( diff / 86400 ))
      (( days == 1 )) && echo "1 day ago" || echo "${days} days ago"
    elif (( diff < 2592000 )); then
      local weeks=$(( diff / 604800 ))
      (( weeks == 1 )) && echo "1 week ago" || echo "${weeks} weeks ago"
    else
      local months=$(( diff / 2592000 ))
      (( months == 1 )) && echo "1 month ago" || echo "${months} months ago"
    fi
  }

  # ── subcommands ──────────────────────────────────────────────
  case "${1:-}" in
    help|-h|--help)
      _play_help
      ;;

    ls)
      local has_playgrounds=false

      if [[ -d "$base" ]] && [[ -n "$(ls -A "$base" 2>/dev/null)" ]]; then
        has_playgrounds=true
        local total=0 total_bytes=0
        local entries=()

        for dir in "$base"/*(N-/om); do
          local name="${dir:t}"
          local size=$(_play_size "$dir")
          local age=$(_play_age "$dir")
          local bytes=$(du -sk "$dir" 2>/dev/null | cut -f1)
          entries+=("$name|$size|$age")
          (( total++ ))
          (( total_bytes += bytes ))
        done

        # convert total KB to human readable
        local total_size
        if (( total_bytes >= 1048576 )); then
          total_size="$(printf '%.1f GB' "$(echo "scale=1; $total_bytes / 1048576" | bc)")"
        elif (( total_bytes >= 1024 )); then
          total_size="$(printf '%.1f MB' "$(echo "scale=1; $total_bytes / 1024" | bc)")"
        else
          total_size="${total_bytes} KB"
        fi

        echo "📂 Playgrounds ($total total, $total_size)\n"

        # find max name length for alignment
        local max_name=0
        for entry in "${entries[@]}"; do
          local n="${entry%%|*}"
          (( ${#n} > max_name )) && max_name=${#n}
        done

        for entry in "${entries[@]}"; do
          local n="${entry%%|*}"
          local rest="${entry#*|}"
          local s="${rest%%|*}"
          local a="${rest#*|}"
          printf "  %-${max_name}s  %8s  %s\n" "$n" "$s" "$a"
        done
      fi

      # ── Antigravity workspaces ──
      local ag_ws="${PLAY_AG_WS_STORAGE}"
      if [[ -d "$ag_ws" ]] && command -v python3 &>/dev/null; then
        local ws_lines
        ws_lines=$(PLAY_AG_WS_STORAGE="$ag_ws" PLAY_DIR="$base" \
          python3 "${_PLAY_PLUGIN_DIR}/play_list_workspaces.py" 2>/dev/null)

        if [[ -n "$ws_lines" ]]; then
          local ws_count=0
          local ws_entries=()

          while IFS= read -r line; do
            ws_entries+=("$line")
            (( ws_count++ ))
          done <<< "$ws_lines"

          if (( ws_count > 0 )); then
            $has_playgrounds && echo ""
            echo "🚀 Antigravity Workspaces ($ws_count total)\n"

            # find max name length for alignment
            local max_ws_name=0
            for entry in "${ws_entries[@]}"; do
              local epoch="${entry%%|*}"
              local rest="${entry#*|}"
              local n="${rest%%|*}"
              (( ${#n} > max_ws_name )) && max_ws_name=${#n}
            done
            # cap name column so paths aren't pushed too far
            (( max_ws_name > 30 )) && max_ws_name=30

            for entry in "${ws_entries[@]}"; do
              local epoch="${entry%%|*}"
              local rest="${entry#*|}"
              local n="${rest%%|*}"
              local p="${rest#*|}"
              local age=$(_play_age_epoch "$epoch")
              # Abbreviate path: replace $HOME with ~
              local display_path="${p/#$HOME/~}"
              printf "  %-${max_ws_name}s  %-40s  %s\n" "$n" "$display_path" "$age"
            done
          fi
        fi
      elif [[ ! -d "$ag_ws" ]]; then
        : # silently skip if Antigravity not installed
      elif ! command -v python3 &>/dev/null; then
        $has_playgrounds && echo ""
        echo "⚠️  python3 required for Antigravity workspace listing" >&2
      fi

      if ! $has_playgrounds && [[ -z "$ws_lines" ]]; then
        echo "No playgrounds or workspaces found." >&2
      fi
      ;;

    rm)
      shift
      local force=false purge=false all=false target=""

      # parse flags
      while [[ $# -gt 0 ]]; do
        case "$1" in
          -f|--force) force=true; shift ;;
          --purge)    purge=true; shift ;;
          --all)      all=true; shift ;;
          -*)         echo "❌ Unknown flag: $1" >&2; return 1 ;;
          *)          target="$1"; shift ;;
        esac
      done

      if [[ ! -d "$base" ]] || [[ -z "$(ls -A "$base" 2>/dev/null)" ]]; then
        echo "No playgrounds to remove." >&2
        return 0
      fi

      # ── rm --all ──
      if $all; then
        local count=0 total_kb=0
        for dir in "$base"/*(N-/); do
          (( count++ ))
          (( total_kb += $(du -sk "$dir" 2>/dev/null | cut -f1) ))
        done
        local total_hr=$(_play_size "$base")

        if ! $force; then
          local verb="Trash" confirm_word="yes"
          $purge && verb="PERMANENTLY DELETE"
          echo -n "⚠️  This will $verb ALL $count playgrounds ($total_hr total).\nType 'yes' to confirm: "
          read -r response
          [[ "$response" != "yes" ]] && echo "Cancelled." && return 0
        fi

        if $purge; then
          rm -rf "$base"/*(N-/)
          echo "💀 Purged $count playgrounds ($total_hr)"
        else
          /usr/bin/trash "$base"/*(N-/)
          echo "✅ Trashed $count playgrounds ($total_hr) — recoverable from Trash"
        fi
        return 0
      fi

      # ── rm (interactive picker) ──
      if [[ -z "$target" ]]; then
        local dirs=()
        for dir in "$base"/*(N-/om); do
          dirs+=("${dir:t}")
        done

        echo "📋 Playgrounds:"
        local i=1
        for name in "${dirs[@]}"; do
          local d="$base/$name"
          printf "  %d) %-20s %8s  %s\n" "$i" "$name" "$(_play_size "$d")" "$(_play_age "$d")"
          (( i++ ))
        done
        echo ""
        echo -n "Pick one to trash (or q to quit): "
        read -r choice
        [[ "$choice" == "q" || -z "$choice" ]] && echo "Cancelled." && return 0

        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#dirs[@]} )); then
          target="${dirs[$choice]}"
        else
          echo "❌ Invalid choice." >&2
          return 1
        fi
      fi

      # ── rm <name> ──
      local dir="$base/$target"
      if [[ ! -d "$dir" ]]; then
        echo "❌ Playground '$target' not found." >&2
        return 1
      fi

      local size=$(_play_size "$dir")

      if ! $force; then
        local verb="Trash"
        $purge && verb="PERMANENTLY DELETE"
        echo -n "🗑  $verb playground '$target' ($size)? [y/N] "
        read -r confirm
        [[ ! "$confirm" =~ ^[Yy]$ ]] && echo "Cancelled." && return 0
      fi

      if $purge; then
        rm -rf "$dir"
        echo "💀 Purged '$target' ($size)"
      else
        /usr/bin/trash "$dir"
        echo "✅ Trashed '$target' ($size) — recoverable from Trash"
      fi
      ;;

    *)
      local name="${1:-$(date +%Y%m%d-%H%M%S)}"

      # Check if it matches an existing playground first
      if [[ -d "$base/$name" ]]; then
        ${(z)PLAY_OPEN_CMD} "$base/$name"
        echo "🎮 Playground: $base/$name"
        return 0
      fi

      # Check if it matches an Antigravity workspace
      if [[ -n "$1" ]] && command -v python3 &>/dev/null && [[ -d "${PLAY_AG_WS_STORAGE}" ]]; then
        local ws_match
        ws_match=$(PLAY_AG_WS_STORAGE="${PLAY_AG_WS_STORAGE}" PLAY_DIR="$base" \
          python3 "${_PLAY_PLUGIN_DIR}/play_list_workspaces.py" 2>/dev/null \
          | while IFS='|' read -r _epoch ws_name ws_path; do
              if [[ "$ws_name" == "$name" ]]; then
                echo "$ws_path"
                break
              fi
            done)
        if [[ -n "$ws_match" ]]; then
          ${(z)PLAY_OPEN_CMD} "$ws_match"
          echo "🚀 Workspace: $ws_match"
          return 0
        fi
      fi

      # Otherwise create a new playground
      local dir="$base/$name"
      if ! mkdir -p "$dir" 2>/dev/null; then
        echo "❌ Failed to create $dir" >&2
        return 1
      fi
      ${(z)PLAY_OPEN_CMD} "$dir"
      echo "🎮 Playground: $dir"
      ;;
  esac
}

# ── tab completion ─────────────────────────────────────────────
_play() {
  local base="${PLAY_DIR:-$HOME/agy-playgrounds}"
  local ag_ws="${PLAY_AG_WS_STORAGE:-$HOME/Library/Application Support/Antigravity/User/workspaceStorage}"

  _play_dirs() {
    local dirs=()
    if [[ -d "$base" ]]; then
      for d in "$base"/*(N-/); do
        dirs+=("${d:t}")
      done
    fi
    compadd -a dirs
  }

  _play_workspaces() {
    if [[ -d "$ag_ws" ]] && command -v python3 &>/dev/null; then
      local -a ws_names
      local raw
      raw=$(PLAY_AG_WS_STORAGE="$ag_ws" PLAY_DIR="$base" \
        python3 "${_PLAY_PLUGIN_DIR}/play_list_workspaces.py" 2>/dev/null)
      [[ -z "$raw" ]] && return
      # Extract just the name field (epoch|NAME|path) from each line
      local line
      for line in "${(@f)raw}"; do
        local rest="${line#*|}"
        ws_names+=("${rest%%|*}")
      done
      compadd -a ws_names
    fi
  }

  local -a subcmds=(
    'ls:List playgrounds & Antigravity workspaces'
    'rm:Trash or delete a playground'
    'help:Show help'
  )

  if (( CURRENT == 2 )); then
    _describe 'subcommand' subcmds || { _play_dirs; _play_workspaces }
  elif (( CURRENT == 3 )) && [[ "${words[2]}" == "rm" ]]; then
    local -a rm_flags=(
      '--all:Trash all playgrounds'
      '--purge:Permanently delete (no recovery)'
      '-f:Skip confirmation'
      '--force:Skip confirmation'
    )
    _describe 'flag' rm_flags || _play_dirs
  elif (( CURRENT >= 4 )) && [[ "${words[2]}" == "rm" ]]; then
    local -a rm_flags=(
      '--purge:Permanently delete (no recovery)'
      '-f:Skip confirmation'
      '--force:Skip confirmation'
    )
    _describe 'flag' rm_flags || _play_dirs
  fi
}
compdef _play play
