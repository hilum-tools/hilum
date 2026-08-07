<#
.SYNOPSIS
Hilum installer for Windows — downloads the release build for this machine, verifies it, and puts it
somewhere you can run it from.

.DESCRIPTION
The Windows sibling of install.sh. Run it with:

    irm https://hilum.tools/install.ps1 | iex

Re-running it is how you upgrade: the install is idempotent and replaces whatever is there.

It does NOT change your PATH unless you ask with -AddToPath. A script piped into a shell cannot ask,
and rewriting a user's environment without asking is not a thing to do quietly — so by default it
prints what to add and leaves the decision where it belongs.

.PARAMETER Version
Install this exact version instead of the latest release. Also settable as $env:HILUM_VERSION.

.PARAMETER To
Install here instead of %LOCALAPPDATA%\Hilum\bin. Also settable as $env:HILUM_INSTALL_DIR.

.PARAMETER Force
Overwrite an existing binary without asking.

.PARAMETER AddToPath
Append the install directory to the USER PATH (the per-user environment variable, not the machine one).
#>

[CmdletBinding()]
param(
    [string]$Version = $env:HILUM_VERSION,
    [string]$To = $env:HILUM_INSTALL_DIR,
    [switch]$Force,
    [switch]$AddToPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Repo = 'hilum-tools/hilum'
$Bin = 'hilum'
$Api = "https://api.github.com/repos/$Repo/releases"
$Dl = "https://github.com/$Repo/releases/download"

# Windows PowerShell 5.1 still negotiates TLS 1.0 by default, which GitHub refuses. Setting this is
# harmless on PowerShell 7+, where it is already the default.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Fail([string]$Message) { Write-Error "install.ps1: $Message"; exit 1 }

# --- platform ------------------------------------------------------------------------------------
$arch = switch ($env:PROCESSOR_ARCHITECTURE) {
    'AMD64' { 'x86_64' }
    'ARM64' { 'aarch64' }
    # A 32-bit PowerShell on a 64-bit machine reports x86 here, and the real architecture is in
    # PROCESSOR_ARCHITEW6432. Reading only the first variable would hand an ARM machine an x86 binary.
    'x86' { if ($env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') { 'aarch64' } elseif ($env:PROCESSOR_ARCHITEW6432 -eq 'AMD64') { 'x86_64' } else { Fail 'this build needs a 64-bit Windows' } }
    default { Fail "unsupported architecture: $($env:PROCESSOR_ARCHITECTURE)" }
}
$target = "$arch-pc-windows-msvc"

# --- version -------------------------------------------------------------------------------------
# The latest-release endpoint excludes prereleases, so a release candidate is never served here by
# accident. Someone who wants one names it with -Version.
if (-not $Version) {
    try { $Version = (Invoke-RestMethod -Uri "$Api/latest" -Headers @{ 'User-Agent' = 'hilum-installer' }).tag_name }
    catch { Fail "could not determine the latest version. Pass -Version <v>, or check that $Repo has a published release." }
}
$Version = $Version -replace '^v', ''

$archive = "$Bin-$Version-$target.zip"
$sums = "$Bin-$Version-SHA256SUMS"

if (-not $To) { $To = Join-Path $env:LOCALAPPDATA 'Hilum\bin' }

# --- download + verify ---------------------------------------------------------------------------
$tmp = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
try {
    Write-Host "hilum $Version for $target"
    try { Invoke-WebRequest -Uri "$Dl/v$Version/$archive" -OutFile (Join-Path $tmp $archive) -UseBasicParsing }
    catch { Fail "download failed. Is $Version a published release for $target?" }

    # Verification is not optional. A release without a sums file is a broken release, so a missing one
    # fails rather than becoming a reason to skip the check.
    try { Invoke-WebRequest -Uri "$Dl/v$Version/$sums" -OutFile (Join-Path $tmp $sums) -UseBasicParsing }
    catch { Fail "no checksum file in release v$Version — refusing to install unverified" }

    $line = Select-String -Path (Join-Path $tmp $sums) -Pattern ([regex]::Escape($archive) + '$') | Select-Object -First 1
    if (-not $line) { Fail "$archive is not listed in $sums — refusing to install unverified" }
    $expected = ($line.Line -split '\s+')[0]
    $actual = (Get-FileHash -Path (Join-Path $tmp $archive) -Algorithm SHA256).Hash.ToLower()
    if ($expected.ToLower() -ne $actual) { Fail "checksum mismatch for ${archive}: expected $expected, got $actual" }
    Write-Host 'checksum ok'

    # --- install -----------------------------------------------------------------------------------
    Expand-Archive -Path (Join-Path $tmp $archive) -DestinationPath $tmp -Force
    $src = Join-Path $tmp "$Bin.exe"
    if (-not (Test-Path $src)) { Fail "the archive did not contain a $Bin.exe" }

    New-Item -ItemType Directory -Path $To -Force | Out-Null
    $dest = Join-Path $To "$Bin.exe"
    if ((Test-Path $dest) -and -not $Force) {
        # A running binary cannot be replaced on Windows, unlike on Unix where the old inode survives
        # the swap. Say which process to stop rather than failing with a bare access-denied.
        $running = Get-Process -Name $Bin -ErrorAction SilentlyContinue
        if ($running) { Fail "$Bin is running (PID $($running.Id -join ', ')). Stop it, or re-run with -Force after stopping the daemon: $Bin daemon stop" }
    }
    Move-Item -Path $src -Destination $dest -Force
    Write-Host "installed $dest"

    # Record how this binary arrived, so the updater picks the right upgrade path later. Written by the
    # installer because the installer is the only party that knows the truth.
    $markerDir = Join-Path $HOME '.hilum\local'
    New-Item -ItemType Directory -Path $markerDir -Force | Out-Null
    @{ channel = 'tarball'; version = $Version; target = $target; installed_to = $To } |
        ConvertTo-Json -Compress | Set-Content -Path (Join-Path $markerDir 'install.json') -Encoding utf8
}
finally {
    Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

# --- PATH ----------------------------------------------------------------------------------------
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($userPath -notlike "*$To*") {
    if ($AddToPath) {
        [Environment]::SetEnvironmentVariable('Path', "$userPath;$To", 'User')
        Write-Host "added $To to your user PATH — open a new terminal for it to take effect"
    }
    else {
        Write-Host ''
        Write-Host "$To is not on your PATH. Add it with:"
        Write-Host "  [Environment]::SetEnvironmentVariable('Path', [Environment]::GetEnvironmentVariable('Path','User') + ';$To', 'User')"
        Write-Host '  (or re-run this installer with -AddToPath)'
    }
}

Write-Host ''
Write-Host "Run '$Bin --version' to confirm, and '$Bin --help' to see what it does."
