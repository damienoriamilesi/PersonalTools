<#
.SYNOPSIS
    Reproduces the Oh My Posh terminal setup on a new Windows machine.

.DESCRIPTION
    Idempotent - safe to run again. It:
      1. Installs/updates Oh My Posh (winget)
      2. Installs the Meslo Nerd Font (provides "MesloLGM Nerd Font")
      3. Installs the posh-git module
      4. Writes the custom agnosterplus.omp.json theme next to each PowerShell profile
      5. Adds the init lines to the Windows PowerShell 5.1 and PowerShell 7 profiles
      6. Sets "MesloLGM Nerd Font" as the default font in Windows Terminal
    Every file it changes is backed up first as <file>.bak-<timestamp>.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\install-oh-my-posh.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

if ($IsMacOS -or $IsLinux) {
    throw 'This script is for Windows. On macOS run install-oh-my-posh.sh instead.'
}

$FontFace      = 'MesloLGM Nerd Font'
$FontFile      = 'MesloLGMNerdFont-Regular.ttf'
$ThemeFileName = 'agnosterplus.omp.json'
$Stamp         = Get-Date -Format 'yyyyMMdd-HHmmss'
$Utf8NoBom     = New-Object System.Text.UTF8Encoding $false
$BlockStart    = '# >>> oh-my-posh setup >>>'
$BlockEnd      = '# <<< oh-my-posh setup <<<'

# Custom theme (agnosterplus variant: right-hand clock + session / path / git).
$ThemeJson = @'
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
'@

$ProfileBlock = @"
$BlockStart
oh-my-posh init pwsh --config "`$PSScriptRoot\$ThemeFileName" | Invoke-Expression
Import-Module posh-git
$BlockEnd
"@

function Write-Step([string]$Message) { Write-Host "`n==> $Message" -ForegroundColor Cyan }
function Write-Ok([string]$Message)   { Write-Host "    $Message" -ForegroundColor Green }
function Write-Warn([string]$Message) { Write-Host "    $Message" -ForegroundColor Yellow }

function Update-SessionPath {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
}

function Backup-File([string]$Path) {
    if (Test-Path $Path) { Copy-Item $Path "$Path.bak-$Stamp" -Force }
}

# PowerShell hosts present on this machine: Windows PowerShell 5.1 and (optionally) PowerShell 7.
$Docs  = [Environment]::GetFolderPath('MyDocuments')
$Hosts = @([pscustomobject]@{ Exe = 'powershell.exe'; ProfileDir = Join-Path $Docs 'WindowsPowerShell' })
if (Get-Command pwsh.exe -ErrorAction SilentlyContinue) {
    $Hosts += [pscustomobject]@{ Exe = 'pwsh.exe'; ProfileDir = Join-Path $Docs 'PowerShell' }
}

# --- 1. Oh My Posh ---------------------------------------------------------
Write-Step 'Oh My Posh'
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw 'winget not found. Install "App Installer" from the Microsoft Store, then rerun.'
}
$wingetArgs = @('--id', 'JanDeDobbeleer.OhMyPosh', '-e', '--source', 'winget',
                '--accept-source-agreements', '--accept-package-agreements')
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    winget upgrade @wingetArgs | Out-Host    # non-zero exit when already up to date - harmless
} else {
    winget install @wingetArgs | Out-Host
    Update-SessionPath
}
if (-not (Get-Command oh-my-posh -ErrorAction SilentlyContinue)) {
    $ompBin = Join-Path $env:LOCALAPPDATA 'Programs\oh-my-posh\bin'
    if (Test-Path $ompBin) { $env:Path += ";$ompBin" }
}
if (-not (Get-Command oh-my-posh -ErrorAction SilentlyContinue)) {
    throw 'oh-my-posh is still not on PATH. Open a new terminal and rerun this script.'
}
Write-Ok ("oh-my-posh " + (oh-my-posh version))

# --- 2. Nerd Font ----------------------------------------------------------
Write-Step "Font: $FontFace"
$fontDirs = @("$env:LOCALAPPDATA\Microsoft\Windows\Fonts", "$env:WINDIR\Fonts")
if (Get-ChildItem $fontDirs -Filter $FontFile -ErrorAction SilentlyContinue) {
    Write-Ok 'Already installed'
} else {
    oh-my-posh font install Meslo | Out-Host
    Write-Ok 'Installed Meslo Nerd Font family'
}

# --- 3. posh-git (for each PowerShell host) -------------------------------
Write-Step 'posh-git module'
$installPoshGit = @'
if (Get-Module -ListAvailable posh-git) { 'already installed'; return }
if (-not (Get-PackageProvider -ListAvailable -Name NuGet -ErrorAction SilentlyContinue)) {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force | Out-Null
}
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
Install-Module posh-git -Scope CurrentUser -Force -AllowClobber
'installed'
'@
$encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($installPoshGit))
foreach ($h in $Hosts) {
    $result = & $h.Exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded
    Write-Ok "$($h.Exe): $result"
}

# --- 4 & 5. Theme + profiles ----------------------------------------------
Write-Step 'Theme and PowerShell profiles'
foreach ($h in $Hosts) {
    New-Item -ItemType Directory -Force -Path $h.ProfileDir | Out-Null

    $themePath = Join-Path $h.ProfileDir $ThemeFileName
    Backup-File $themePath
    [IO.File]::WriteAllText($themePath, $ThemeJson, $Utf8NoBom)

    $profilePath = Join-Path $h.ProfileDir 'Microsoft.PowerShell_profile.ps1'
    $existing = if (Test-Path $profilePath) { Get-Content $profilePath -Raw } else { '' }
    if ($null -eq $existing) { $existing = '' }
    Backup-File $profilePath

    # Drop a previous managed block and any stray active init lines, then append ours.
    $clean = [regex]::Replace($existing, "(?s)$([regex]::Escape($BlockStart)).*?$([regex]::Escape($BlockEnd))\r?\n?", '')
    $clean = ($clean -split "\r?\n" | Where-Object {
        $_ -notmatch '^\s*oh-my-posh\s+init\b' -and $_ -notmatch '^\s*Import-Module\s+posh-git\b'
    }) -join "`r`n"
    $newProfile = ($clean.TrimEnd() + "`r`n`r`n" + $ProfileBlock + "`r`n").TrimStart()
    [IO.File]::WriteAllText($profilePath, $newProfile, $Utf8NoBom)
    Write-Ok $profilePath
}

# Profiles are scripts: they will not load under the default "Restricted" policy.
if ((Get-ExecutionPolicy) -in 'Restricted', 'AllSigned', 'Undefined') {
    try {
        Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
        Write-Ok 'Execution policy (CurrentUser) set to RemoteSigned'
    } catch {
        Write-Warn "Could not change execution policy (probably enforced by Group Policy): $($_.Exception.Message)"
    }
}

# --- 6. Windows Terminal font ---------------------------------------------
Write-Step 'Windows Terminal default font'
$wtCandidates = @(
    "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
    "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json",
    "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
)
$wtSettings = @($wtCandidates | Where-Object { Test-Path $_ })

if ($wtSettings.Count -eq 0) {
    Write-Warn 'No Windows Terminal settings.json found. Open Windows Terminal once, close it, and rerun this script.'
}
foreach ($path in $wtSettings) {
    try {
        $raw  = Get-Content $path -Raw
        # settings.json is JSONC; strip whole-line // comments so ConvertFrom-Json (PS 5.1) can parse it.
        $json = (($raw -split "\r?\n") | Where-Object { $_ -notmatch '^\s*//' }) -join "`n" | ConvertFrom-Json

        if ($json.profiles -is [array]) {
            $json.profiles = [pscustomobject]@{ defaults = [pscustomobject]@{}; list = $json.profiles }
        }
        if (-not $json.profiles.PSObject.Properties['defaults']) {
            $json.profiles | Add-Member -NotePropertyName defaults -NotePropertyValue ([pscustomobject]@{})
        }
        $defaults = $json.profiles.defaults
        if (-not $defaults.PSObject.Properties['font']) {
            $defaults | Add-Member -NotePropertyName font -NotePropertyValue ([pscustomobject]@{})
        }

        if ($defaults.font.PSObject.Properties['face'] -and $defaults.font.face -eq $FontFace) {
            Write-Ok "Already set: $path"
            continue
        }
        if ($defaults.font.PSObject.Properties['face']) { $defaults.font.face = $FontFace }
        else { $defaults.font | Add-Member -NotePropertyName face -NotePropertyValue $FontFace }
        if ($defaults.PSObject.Properties['fontFace']) { $defaults.PSObject.Properties.Remove('fontFace') }

        Backup-File $path
        [IO.File]::WriteAllText($path, ($json | ConvertTo-Json -Depth 100), $Utf8NoBom)
        Write-Ok "Updated: $path"
    } catch {
        Write-Warn "Could not update $path ($($_.Exception.Message)). Set the font manually: Settings > Defaults > Appearance > Font face = $FontFace"
    }
}

Write-Host "`nDone. Close and reopen Windows Terminal to see the new prompt." -ForegroundColor Green
