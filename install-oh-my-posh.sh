#!/usr/bin/env bash
#
# Reproduces the Oh My Posh terminal setup on a new Mac.
#
# Idempotent - safe to run again. It:
#   1. Installs Homebrew if missing
#   2. Installs/updates Oh My Posh
#   3. Installs the Meslo Nerd Font (provides "MesloLGM Nerd Font")
#   4. Writes the custom agnosterplus.omp.json theme to ~/.config/oh-my-posh/
#   5. Adds the init line to ~/.zshrc (and ~/.bash_profile if bash is your shell)
#   6. If PowerShell (pwsh) is installed: installs posh-git and configures its profile too
#   7. Sets MesloLGM Nerd Font as the font of the default Terminal.app profile
# Every file it changes is backed up first as <file>.bak-<timestamp>.
#
# Usage:  bash install-oh-my-posh.sh

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script is for macOS. On Windows run install-oh-my-posh.ps1 instead." >&2
  exit 1
fi

FONT_PS_NAME="MesloLGMNF-Regular"   # PostScript name of "MesloLGM Nerd Font" Regular
THEME_DIR="$HOME/.config/oh-my-posh"
THEME_FILE="$THEME_DIR/agnosterplus.omp.json"
STAMP="$(date +%Y%m%d-%H%M%S)"
BLOCK_START="# >>> oh-my-posh setup >>>"
BLOCK_END="# <<< oh-my-posh setup <<<"

step() { printf '\n\033[36m==> %s\033[0m\n' "$*"; }
ok()   { printf '    \033[32m%s\033[0m\n' "$*"; }
warn() { printf '    \033[33m%s\033[0m\n' "$*"; }

backup() { [[ -f "$1" ]] && cp "$1" "$1.bak-$STAMP" || true; }

# Replace the managed block in a file (or append it if absent).
#   $1 = file, $2 = block body (without markers)
write_block() {
  local file="$1" body="$2"
  mkdir -p "$(dirname "$file")"
  touch "$file"
  backup "$file"
  awk -v s="$BLOCK_START" -v e="$BLOCK_END" '
    $0 == s { skip = 1; next }
    $0 == e { skip = 0; next }
    skip { next }
    /^[[:space:]]*$/ { blank = blank $0 "\n"; next }   # hold blank lines...
    { printf "%s", blank; blank = ""; print }          # ...emit only if followed by content
  ' "$file" > "$file.tmp.$STAMP"
  mv "$file.tmp.$STAMP" "$file"
  printf '\n%s\n%s\n%s\n' "$BLOCK_START" "$body" "$BLOCK_END" >> "$file"
  ok "$file"
}

# --- 1. Homebrew -----------------------------------------------------------
step "Homebrew"
if ! command -v brew >/dev/null 2>&1; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi
ok "$(brew --version | head -n1)"

# --- 2. Oh My Posh ---------------------------------------------------------
step "Oh My Posh"
if brew list --formula oh-my-posh >/dev/null 2>&1; then
  brew upgrade jandedobbeleer/oh-my-posh/oh-my-posh || true
else
  brew install jandedobbeleer/oh-my-posh/oh-my-posh
fi
ok "oh-my-posh $(oh-my-posh version)"

# --- 3. Nerd Font ----------------------------------------------------------
step "Font: MesloLGM Nerd Font"
if brew list --cask font-meslo-lg-nerd-font >/dev/null 2>&1; then
  ok "Already installed"
else
  brew install --cask font-meslo-lg-nerd-font
  ok "Installed"
fi

# --- 4. Theme --------------------------------------------------------------
step "Theme"
mkdir -p "$THEME_DIR"
backup "$THEME_FILE"
cat > "$THEME_FILE" <<'JSON'
{
  "$schema": "https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/schema.json",
  "blocks": [
    {
      "type": "rprompt",
      "segments": [
        {
          "foreground": "#007ACC",
          "options": {
            "time_format": "15:04:05"
          },
          "style": "plain",
          "template": " {{ .CurrentDate | date .Format }} ",
          "type": "time"
        }
      ]
    },
    {
      "alignment": "left",
      "segments": [
        {
          "background": "#ffffff",
          "foreground": "#100e23",
          "powerline_symbol": "\ue0b0",
          "style": "powerline",
          "template": " {{ .UserName }}@{{ .HostName }} ",
          "type": "session"
        },
        {
          "background": "#91ddff",
          "foreground": "#100e23",
          "powerline_symbol": "\ue0b0",
          "options": {
            "folder_icon": "\uf115",
            "folder_separator_icon": " \ue0b1 ",
            "home_icon": "\ueb06",
            "style": "agnoster"
          },
          "style": "powerline",
          "template": " {{ .Path }} ",
          "type": "path"
        },
        {
          "background": "#95ffa4",
          "foreground": "#193549",
          "powerline_symbol": "\ue0b0",
          "style": "powerline",
          "template": " {{ .HEAD }} ",
          "type": "git"
        }
      ],
      "type": "prompt"
    }
  ],
  "final_space": true,
  "version": 4
}
JSON
ok "$THEME_FILE"

# --- 5. Shell profiles -----------------------------------------------------
step "Shell profiles"
write_block "$HOME/.zshrc" \
  'eval "$(oh-my-posh init zsh --config "$HOME/.config/oh-my-posh/agnosterplus.omp.json")"'
if [[ "${SHELL:-}" == */bash ]]; then
  write_block "$HOME/.bash_profile" \
    'eval "$(oh-my-posh init bash --config "$HOME/.config/oh-my-posh/agnosterplus.omp.json")"'
fi

# --- 6. PowerShell (optional) ---------------------------------------------
if command -v pwsh >/dev/null 2>&1; then
  step "PowerShell 7 (pwsh)"
  pwsh -NoProfile -Command '
    if (-not (Get-Module -ListAvailable posh-git)) {
      Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
      Install-Module posh-git -Scope CurrentUser -Force -AllowClobber
    }'
  ok "posh-git ready"
  write_block "$HOME/.config/powershell/Microsoft.PowerShell_profile.ps1" \
'oh-my-posh init pwsh --config "$HOME/.config/oh-my-posh/agnosterplus.omp.json" | Invoke-Expression
Import-Module posh-git'
fi

# --- 7. Terminal font ------------------------------------------------------
step "Terminal.app default font"
if osascript -e "tell application \"Terminal\" to set font name of default settings to \"$FONT_PS_NAME\"" >/dev/null 2>&1; then
  ok "Terminal.app default profile now uses MesloLGM Nerd Font"
else
  warn "Could not set it automatically. Terminal > Settings > Profiles > Text > Font > MesloLGM Nerd Font"
fi
if [[ -d "/Applications/iTerm.app" ]]; then
  warn "iTerm2 detected: set Settings > Profiles > Text > Font to 'MesloLGM Nerd Font' manually."
fi

printf '\n\033[32mDone. Open a new terminal window to see the new prompt.\033[0m\n'
