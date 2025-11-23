# fast-syntax-highlighting-filetypes
# Adds LS_COLORS-based file type highlighting to fast-syntax-highlighting
#
# This plugin wraps FSH's _zsh_highlight function to colorize path arguments
# based on file type (directory, executable, symlink, etc.) and file extension
# using LS_COLORS.

# Load zsh/stat module for permission checks
zmodload zsh/stat 2>/dev/null

# Associative array to cache parsed LS_COLORS
typeset -gA _fsh_ft_colors

# Cache for permission checks (cleared each highlight cycle)
typeset -gA _fsh_ft_perm_cache

# Global variable for return values (avoids subshells/echo in ZLE context)
typeset -g _fsh_ft_reply

# Check if path is other-writable (o+w permission)
# Uses cache to avoid repeated stat calls
_fsh_ft_is_other_writable() {
  local target="$1"

  # Check cache first
  if [[ -n "${_fsh_ft_perm_cache[$target]+set}" ]]; then
    # Return cached result (0 = other-writable, 1 = not)
    return "${_fsh_ft_perm_cache[$target]}"
  fi

  local result=1  # Default: not other-writable
  local -a statinfo

  # Try zstat first (available after zmodload zsh/stat)
  if zstat -A statinfo +mode "$target" 2>/dev/null; then
    # statinfo[1] is like "drwxr-xr-x", position 9 is other-write
    [[ ${statinfo[1][9]} == "w" ]] && result=0
  else
    # Fallback: check permission bits directly using stat command
    local mode
    # Try GNU stat first (Linux), then BSD stat (macOS)
    if mode=$(command stat -c '%a' "$target" 2>/dev/null || command stat -f '%Lp' "$target" 2>/dev/null); then
      # Check if other-write bit is set (mode & 002)
      [[ ${mode: -1} == [2367] ]] && result=0
    fi
  fi

  # Cache the result
  _fsh_ft_perm_cache[$target]=$result
  return $result
}

# Parse LS_COLORS into an associative array
_fsh_ft_parse_ls_colors() {
  _fsh_ft_colors=()

  [[ -z "$LS_COLORS" ]] && return

  local -a parts
  parts=("${(@s.:.)LS_COLORS}")

  local part key value
  for part in "${parts[@]}"; do
    [[ "$part" == *"="* ]] || continue
    key="${part%%=*}"
    value="${part#*=}"
    _fsh_ft_colors[$key]="$value"
  done
}

# Check for text attributes in code and append to _fsh_ft_reply
# Strips color sequences (38;2;R;G;B, 48;2;R;G;B, 38;5;N, 48;5;N) before checking
# to avoid false positives (e.g., ;2; in 38;2; matching dim, ;5; in 38;5; matching blink)
_fsh_ft_add_attributes() {
  setopt localoptions extended_glob
  local code="$1"

  # Remove 24-bit color sequences: 38;2;R;G;B and 48;2;R;G;B
  # Pattern: 38;2; or 48;2; followed by up to 3 numbers separated by semicolons
  local sanitized="$code"
  # Remove 38;2;N;N;N and 48;2;N;N;N patterns
  sanitized="${sanitized//38;2;[0-9]#;[0-9]#;[0-9]#/}"
  sanitized="${sanitized//48;2;[0-9]#;[0-9]#;[0-9]#/}"
  # Remove 38;5;N and 48;5;N patterns
  sanitized="${sanitized//38;5;[0-9]#/}"
  sanitized="${sanitized//48;5;[0-9]#/}"

  # Now check for attributes in sanitized code (won't false-match color sequences)
  [[ ";$sanitized;" == *";1;"* || ";$sanitized;" == *";01;"* ]] && _fsh_ft_reply+=",bold"
  [[ ";$sanitized;" == *";2;"* || ";$sanitized;" == *";02;"* ]] && _fsh_ft_reply+=",dim"
  [[ ";$sanitized;" == *";3;"* || ";$sanitized;" == *";03;"* ]] && _fsh_ft_reply+=",italic"
  [[ ";$sanitized;" == *";4;"* || ";$sanitized;" == *";04;"* ]] && _fsh_ft_reply+=",underline"
  [[ ";$sanitized;" == *";5;"* || ";$sanitized;" == *";05;"* ]] && _fsh_ft_reply+=",blink"
  [[ ";$sanitized;" == *";7;"* || ";$sanitized;" == *";07;"* ]] && _fsh_ft_reply+=",standout"
  [[ ";$sanitized;" == *";9;"* || ";$sanitized;" == *";09;"* ]] && _fsh_ft_reply+=",strikethrough"
}

# Convert LS_COLORS code to zsh highlight format
# Sets _fsh_ft_reply with result
_fsh_ft_code_to_highlight() {
  local code="$1"
  _fsh_ft_reply=""

  # Handle 38;2;R;G;B format (24-bit true color)
  if [[ "$code" == *"38;2;"* ]]; then
    local rgb_part="${code#*38;2;}"
    local r="${rgb_part%%;*}"
    rgb_part="${rgb_part#*;}"
    local g="${rgb_part%%;*}"
    rgb_part="${rgb_part#*;}"
    local b="${rgb_part%%;*}"
    b="${b%%:*}"
    # Validate RGB values are numeric before using printf
    if [[ "$r" == <0-255> && "$g" == <0-255> && "$b" == <0-255> ]]; then
      _fsh_ft_reply="fg=#$(printf '%02x%02x%02x' "$r" "$g" "$b")"
    fi

    # Check for 24-bit background (48;2;R;G;B format)
    if [[ "$code" == *"48;2;"* ]]; then
      rgb_part="${code#*48;2;}"
      r="${rgb_part%%;*}"
      rgb_part="${rgb_part#*;}"
      g="${rgb_part%%;*}"
      rgb_part="${rgb_part#*;}"
      b="${rgb_part%%;*}"
      b="${b%%:*}"
      if [[ "$r" == <0-255> && "$g" == <0-255> && "$b" == <0-255> ]]; then
        [[ -n "$_fsh_ft_reply" ]] && _fsh_ft_reply+=","
        _fsh_ft_reply+="bg=#$(printf '%02x%02x%02x' "$r" "$g" "$b")"
      fi
    fi

    # Check for text attributes (using helper to avoid false positives)
    _fsh_ft_add_attributes "$code"
    return 0
  fi

  # Handle 48;2;R;G;B format (24-bit background only)
  if [[ "$code" == *"48;2;"* ]]; then
    local rgb_part="${code#*48;2;}"
    local r="${rgb_part%%;*}"
    rgb_part="${rgb_part#*;}"
    local g="${rgb_part%%;*}"
    rgb_part="${rgb_part#*;}"
    local b="${rgb_part%%;*}"
    b="${b%%:*}"
    if [[ "$r" == <0-255> && "$g" == <0-255> && "$b" == <0-255> ]]; then
      _fsh_ft_reply="bg=#$(printf '%02x%02x%02x' "$r" "$g" "$b")"
    fi
    _fsh_ft_add_attributes "$code"
    return 0
  fi

  # Handle 38;5;N format (256 colors) - most common case
  if [[ "$code" == *"38;5;"* ]]; then
    local color_num="${code#*38;5;}"  # Use # not ## to get first occurrence
    color_num="${color_num%%;*}"
    color_num="${color_num%%:*}"
    _fsh_ft_reply="fg=$color_num"

    # Check for background (48;5;N format)
    if [[ "$code" == *"48;5;"* ]]; then
      local bg_num="${code#*48;5;}"  # Use # not ## to get first occurrence
      bg_num="${bg_num%%;*}"
      bg_num="${bg_num%%:*}"
      _fsh_ft_reply+=",bg=$bg_num"
    fi

    # Check for text attributes (using helper to avoid false positives)
    _fsh_ft_add_attributes "$code"
    return 0
  fi

  # Handle 48;5;N format (background only, no 256-color foreground)
  if [[ "$code" == *"48;5;"* ]]; then
    local bg_num="${code#*48;5;}"  # Use # not ## to get first occurrence
    bg_num="${bg_num%%;*}"
    bg_num="${bg_num%%:*}"
    _fsh_ft_reply="bg=$bg_num"
    _fsh_ft_add_attributes "$code"
    return 0
  fi

  # Fallback: parse simple ANSI codes
  local -a code_parts
  code_parts=("${(@s.;.)code}")

  local p
  for p in "${code_parts[@]}"; do
    case "$p" in
      # Attributes
      00|0) ;; # Reset/normal - ignore
      01|1) _fsh_ft_reply+="bold," ;;
      02|2) _fsh_ft_reply+="dim," ;;
      03|3) _fsh_ft_reply+="italic," ;;
      04|4) _fsh_ft_reply+="underline," ;;
      05|5) _fsh_ft_reply+="blink," ;;
      07|7) _fsh_ft_reply+="standout," ;;
      09|9) _fsh_ft_reply+="strikethrough," ;;
      # Foreground colors (30-37)
      30) _fsh_ft_reply+="fg=black," ;;
      31) _fsh_ft_reply+="fg=red," ;;
      32) _fsh_ft_reply+="fg=green," ;;
      33) _fsh_ft_reply+="fg=yellow," ;;
      34) _fsh_ft_reply+="fg=blue," ;;
      35) _fsh_ft_reply+="fg=magenta," ;;
      36) _fsh_ft_reply+="fg=cyan," ;;
      37) _fsh_ft_reply+="fg=white," ;;
      # Background colors (40-47)
      40) _fsh_ft_reply+="bg=black," ;;
      41) _fsh_ft_reply+="bg=red," ;;
      42) _fsh_ft_reply+="bg=green," ;;
      43) _fsh_ft_reply+="bg=yellow," ;;
      44) _fsh_ft_reply+="bg=blue," ;;
      45) _fsh_ft_reply+="bg=magenta," ;;
      46) _fsh_ft_reply+="bg=cyan," ;;
      47) _fsh_ft_reply+="bg=white," ;;
      # Bright foreground colors (90-97) - map to 256-color 8-15
      90) _fsh_ft_reply+="fg=8," ;;   # bright black (gray)
      91) _fsh_ft_reply+="fg=9," ;;   # bright red
      92) _fsh_ft_reply+="fg=10," ;;  # bright green
      93) _fsh_ft_reply+="fg=11," ;;  # bright yellow
      94) _fsh_ft_reply+="fg=12," ;;  # bright blue
      95) _fsh_ft_reply+="fg=13," ;;  # bright magenta
      96) _fsh_ft_reply+="fg=14," ;;  # bright cyan
      97) _fsh_ft_reply+="fg=15," ;;  # bright white
      # Bright background colors (100-107)
      100) _fsh_ft_reply+="bg=8," ;;
      101) _fsh_ft_reply+="bg=9," ;;
      102) _fsh_ft_reply+="bg=10," ;;
      103) _fsh_ft_reply+="bg=11," ;;
      104) _fsh_ft_reply+="bg=12," ;;
      105) _fsh_ft_reply+="bg=13," ;;
      106) _fsh_ft_reply+="bg=14," ;;
      107) _fsh_ft_reply+="bg=15," ;;
    esac
  done

  # Remove trailing comma
  _fsh_ft_reply="${_fsh_ft_reply%,}"
}

# Get highlight style for a path based on LS_COLORS
# Sets _fsh_ft_reply with result, returns 1 if no style found
_fsh_ft_get_style() {
  local target="$1"
  local code=""
  _fsh_ft_reply=""

  # Check if path exists
  [[ -e "$target" || -L "$target" ]] || return 1

  # Check file type in order of precedence
  if [[ -L "$target" ]]; then
    if [[ -e "$target" ]]; then
      code="${_fsh_ft_colors[ln]}"
    else
      code="${_fsh_ft_colors[or]:-${_fsh_ft_colors[ln]}}"
    fi
  elif [[ -d "$target" ]]; then
    # Check directory type using actual permission bits
    local is_sticky=0 is_other_writable=0
    [[ -k "$target" ]] && is_sticky=1
    _fsh_ft_is_other_writable "$target" && is_other_writable=1

    if (( is_sticky && is_other_writable )); then
      code="${_fsh_ft_colors[tw]}"
    elif (( is_other_writable )); then
      code="${_fsh_ft_colors[ow]}"
    elif (( is_sticky )); then
      code="${_fsh_ft_colors[st]}"
    else
      code="${_fsh_ft_colors[di]}"
    fi
  elif [[ -f "$target" ]]; then
    if [[ -u "$target" ]]; then
      code="${_fsh_ft_colors[su]}"
    elif [[ -g "$target" ]]; then
      code="${_fsh_ft_colors[sg]}"
    elif [[ -x "$target" ]]; then
      code="${_fsh_ft_colors[ex]}"
    else
      # Check by extension
      local filename="${target##*/}"
      if [[ "$filename" == *.* ]]; then
        local ext=".${filename##*.}"
        code="${_fsh_ft_colors[*$ext]}"
      fi
      # Try full filename match (e.g., Makefile, Dockerfile)
      # LS_COLORS uses *Makefile format for exact matches
      if [[ -z "$code" ]]; then
        code="${_fsh_ft_colors[*$filename]}"
      fi
      # Fall back to regular file color, then normal color
      if [[ -z "$code" ]]; then
        code="${_fsh_ft_colors[fi]:-${_fsh_ft_colors[no]}}"
      fi
    fi
  elif [[ -b "$target" ]]; then
    code="${_fsh_ft_colors[bd]}"
  elif [[ -c "$target" ]]; then
    code="${_fsh_ft_colors[cd]}"
  elif [[ -p "$target" ]]; then
    code="${_fsh_ft_colors[pi]}"
  elif [[ -S "$target" ]]; then
    code="${_fsh_ft_colors[so]}"
  fi

  [[ -z "$code" ]] && return 1

  _fsh_ft_code_to_highlight "$code"
  [[ -n "$_fsh_ft_reply" ]] || return 1
  return 0
}

# Expand tilde in path (handles ~ and ~username)
# Sets _fsh_ft_reply with expanded path
_fsh_ft_expand_tilde() {
  local path="$1"
  _fsh_ft_reply="$path"

  [[ "$path" == "~"* ]] || return 0

  if [[ "$path" == "~/"* || "$path" == "~" ]]; then
    # Simple ~ or ~/path - expand to $HOME
    _fsh_ft_reply="${path/#\~/$HOME}"
  else
    # ~username/path - look up user's home directory
    local tilde_prefix="${path%%/*}"
    local username="${tilde_prefix#\~}"
    local user_home=""
    # Try getent first (Linux)
    user_home="$(getent passwd "$username" 2>/dev/null | cut -d: -f6)"
    # Try dscl on macOS if getent failed
    if [[ -z "$user_home" ]]; then
      user_home="$(dscl . -read /Users/"$username" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
    fi
    # Apply if found, otherwise try common home directories
    if [[ -n "$user_home" && -d "$user_home" ]]; then
      _fsh_ft_reply="${user_home}${path#$tilde_prefix}"
    elif [[ -d "/home/$username" ]]; then
      _fsh_ft_reply="/home/${username}${path#$tilde_prefix}"
    elif [[ -d "/Users/$username" ]]; then
      _fsh_ft_reply="/Users/${username}${path#$tilde_prefix}"
    fi
    # If user not found, leave path unchanged
  fi
}

# Main highlighting function - adds LS_COLORS highlighting to region_highlight
_fsh_ft_highlight() {
  # Only run if LS_COLORS is set
  [[ -z "$LS_COLORS" ]] && return 0

  # Only run if buffer is not empty
  [[ -z "$BUFFER" ]] && return 0

  # Clear permission cache for this cycle
  _fsh_ft_perm_cache=()

  # Parse LS_COLORS if not done or if it changed
  if [[ "${_fsh_ft_last_ls_colors:-}" != "$LS_COLORS" ]]; then
    _fsh_ft_parse_ls_colors
    typeset -g _fsh_ft_last_ls_colors="$LS_COLORS"
  fi

  # Simple word extraction using zsh's built-in word splitting
  local -a words_array
  words_array=("${(z)BUFFER}")

  # Track position in buffer for each word
  local -i pos=0 wlen=0
  local w
  local -i skip_first=1
  local -i past_double_dash=0  # Track if we've seen -- (end of options marker)

  # Variables for highlight manipulation (declared once to avoid issues with repeated local declarations)
  local -a new_highlights
  local h start end

  for w in "${words_array[@]}"; do
    # Skip leading whitespace
    while [[ "${BUFFER:$pos:1}" == [[:space:]] ]]; do
      (( pos++ ))
    done

    wlen="${#w}"

    # Verify we're at the right position by checking the buffer matches the word
    # This handles edge cases where position tracking might drift
    if [[ "${BUFFER:$pos:$wlen}" != "$w" ]]; then
      # Try to find the word starting from current position
      local -i search_pos=$pos
      local -i found=0
      while (( search_pos < ${#BUFFER} )); do
        if [[ "${BUFFER:$search_pos:$wlen}" == "$w" ]]; then
          pos=$search_pos
          found=1
          break
        fi
        (( search_pos++ ))
      done
      (( found )) || { (( pos += wlen )); continue; }
    fi

    # Skip first word (command) and options
    if (( skip_first )); then
      skip_first=0
      (( pos += wlen ))
      continue
    fi

    # Handle -- (end of options marker)
    if [[ "$w" == "--" ]]; then
      past_double_dash=1
      (( pos += wlen ))
      continue
    fi

    # Handle options (only before --)
    if (( ! past_double_dash )) && [[ "$w" == -* ]]; then
      # Check for --option=path pattern
      if [[ "$w" == *=* ]]; then
        local opt_path="${w#*=}"
        local opt_prefix_len=$(( wlen - ${#opt_path} ))
        if [[ -n "$opt_path" ]]; then
          # Unquote path part (handles quotes and backslash escapes)
          # Detects "...", '...', $'...', and $"..." quoting styles
          local opt_is_quoted=0
          [[ "$opt_path" == [\"\']*  || "$opt_path" == "\$'"* || "$opt_path" == '$"'* ]] && opt_is_quoted=1
          local opt_check_path="${(Q)opt_path}"
          # Expand tilde for unquoted paths
          if (( ! opt_is_quoted )) && [[ "$opt_check_path" == "~"* ]]; then
            _fsh_ft_expand_tilde "$opt_check_path"
            opt_check_path="$_fsh_ft_reply"
          fi
          # Try to get style for the path part
          if _fsh_ft_get_style "$opt_check_path"; then
            local path_start=$(( pos + opt_prefix_len ))
            local path_len=${#opt_path}
            # Remove overlapping highlights
            new_highlights=()
            for h in "${region_highlight[@]}"; do
              start="${h%% *}"
              end="${${h#* }%% *}"
              if (( end <= path_start || start >= path_start + path_len )); then
                new_highlights+=("$h")
              fi
            done
            region_highlight=("${new_highlights[@]}")
            region_highlight+=("$path_start $((path_start + path_len)) ${_fsh_ft_reply}")
          fi
        fi
      fi
      (( pos += wlen ))
      continue
    fi

    # Skip empty
    if [[ -z "$w" ]]; then
      continue
    fi

    # Check if word is quoted (before unquoting)
    # Detects "...", '...', $'...', and $"..." quoting styles
    local is_quoted=0
    [[ "$w" == [\"\']*  || "$w" == "\$'"* || "$w" == '$"'* ]] && is_quoted=1

    # Unquote path for existence checking (handles quotes and backslash escapes)
    local check_path="${(Q)w}"

    # Expand tilde only for unquoted paths
    if (( ! is_quoted )) && [[ "$check_path" == "~"* ]]; then
      _fsh_ft_expand_tilde "$check_path"
      check_path="$_fsh_ft_reply"
    fi

    # Get style for this path
    if _fsh_ft_get_style "$check_path"; then
      # Remove any existing highlights for this region (from FSH)
      new_highlights=()
      for h in "${region_highlight[@]}"; do
        start="${h%% *}"
        end="${${h#* }%% *}"
        # Keep highlights that don't overlap with our region
        if (( end <= pos || start >= pos + wlen )); then
          new_highlights+=("$h")
        fi
      done
      region_highlight=("${new_highlights[@]}")
      # Add our highlight
      region_highlight+=("$pos $((pos + wlen)) ${_fsh_ft_reply}")
    fi

    (( pos += wlen ))
  done

  return 0
}

# Wrap FSH's _zsh_highlight function to run our highlighting after it
# This ensures we ALWAYS run immediately after FSH, regardless of which widget triggered it
_fsh_ft_wrap_zsh_highlight() {
  # Check if _zsh_highlight exists (FSH is loaded)
  if (( ! $+functions[_zsh_highlight] )); then
    return 1
  fi

  # Check if already wrapped
  if (( $+functions[_fsh_ft_orig_zsh_highlight] )); then
    return 0
  fi

  # Save original FSH function
  functions[_fsh_ft_orig_zsh_highlight]=$functions[_zsh_highlight]

  # Create wrapper that calls FSH then us
  _zsh_highlight() {
    # Call original FSH highlighting
    _fsh_ft_orig_zsh_highlight "$@"
    local ret=$?
    # Apply our LS_COLORS-based highlighting on top
    _fsh_ft_highlight 2>/dev/null
    return $ret
  }
}

# Initialize: wrap FSH's function
_fsh_ft_wrap_zsh_highlight

# If FSH isn't loaded yet, set up a hook to wrap it when it does load
if (( ! $+functions[_fsh_ft_orig_zsh_highlight] )); then
  # FSH not loaded yet, try again after zshrc finishes loading
  _fsh_ft_deferred_init() {
    _fsh_ft_wrap_zsh_highlight
    # Remove this hook after successful wrap
    if (( $+functions[_fsh_ft_orig_zsh_highlight] )); then
      add-zsh-hook -d precmd _fsh_ft_deferred_init
      unfunction _fsh_ft_deferred_init 2>/dev/null
    fi
  }
  autoload -Uz add-zsh-hook
  add-zsh-hook precmd _fsh_ft_deferred_init
fi
