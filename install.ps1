#requires -Version 5.1
<#
.SYNOPSIS
    Installer/updater for LlamaBox - a PowerShell manager for llama.cpp on Windows.

.DESCRIPTION
    Downloads the LlamaBox scripts straight into memory from GitHub and extracts them
    into an install directory (no temp zip, no git, no admin rights). Re-running it
    upgrades the scripts while preserving your *.args.txt configs and meta.json.

    Quick install (latest):
        irm https://raw.githubusercontent.com/Inndy/LlamaBox/main/install.ps1 | iex

    With options (pass arguments via a script block):
        & ([scriptblock]::Create((irm https://raw.githubusercontent.com/Inndy/LlamaBox/main/install.ps1))) -Dir D:\LlamaBox -NoPath

.PARAMETER Dir
    Install directory. Defaults to %LOCALAPPDATA%\LlamaBox.

.PARAMETER Branch
    Git branch to install from. Defaults to 'main'.

.PARAMETER NoPath
    Skip adding the install directory to your user PATH.

.PARAMETER Update
    After installing, immediately run `llama update` to download the llama.cpp binaries.
#>
param(
    [string]$Dir    = "$env:LOCALAPPDATA\LlamaBox",
    [string]$Branch = 'main',
    [switch]$NoPath,
    [switch]$Update
)

$ErrorActionPreference = 'Stop'
$Repo = 'Inndy/LlamaBox'

Write-Host "Installing LlamaBox to $Dir" -ForegroundColor Cyan

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$zipUrl = "https://codeload.github.com/$Repo/zip/refs/heads/$Branch"
Write-Host "Downloading $zipUrl ..."
$wc = New-Object System.Net.WebClient
$wc.Headers.Add('User-Agent', 'LlamaBox-installer')
try {
    $bytes = $wc.DownloadData($zipUrl)
} finally {
    $wc.Dispose()
}

$null = New-Item -ItemType Directory -Path $Dir -Force
$ms  = New-Object System.IO.MemoryStream(,$bytes)
$zip = New-Object System.IO.Compression.ZipArchive($ms, [System.IO.Compression.ZipArchiveMode]::Read)
try {
    foreach ($entry in $zip.Entries) {
        # Strip the top-level "<repo>-<branch>/" folder GitHub wraps the archive in.
        $rel = $entry.FullName.Substring($entry.FullName.IndexOf('/') + 1)
        if ([string]::IsNullOrEmpty($rel) -or $rel.EndsWith('/')) { continue }

        $dest = Join-Path $Dir ($rel -replace '/', '\')

        # Always refresh code/docs; never clobber user configs on re-install.
        $isCode = $rel -match '\.(ps1|cmd|md)$' -or $rel -ieq 'LICENSE'
        if ((Test-Path $dest) -and -not $isCode) { continue }

        $parent = Split-Path -Parent $dest
        if ($parent) { $null = New-Item -ItemType Directory -Path $parent -Force }

        $in  = $entry.Open()
        $out = [System.IO.File]::Create($dest)
        try { $in.CopyTo($out) } finally { $out.Dispose(); $in.Dispose() }
        Write-Host "  $rel"
    }
} finally {
    $zip.Dispose()
    $ms.Dispose()
}

if (-not $NoPath) {
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $entries  = @($userPath -split ';' | Where-Object { $_ -ne '' })
    if ($entries -notcontains $Dir) {
        $newPath = (@($entries) + $Dir) -join ';'
        [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
        $env:Path = "$env:Path;$Dir"
        Write-Host "Added $Dir to your user PATH (restart your shell to pick it up)." -ForegroundColor Green
    } else {
        Write-Host "$Dir is already on your user PATH." -ForegroundColor Green
    }
}

if ($Update) {
    Write-Host "Running llama update ..." -ForegroundColor Cyan
    & "$Dir\llama.ps1" update
}

Write-Host ""
Write-Host "Done. Next steps:" -ForegroundColor Cyan
if ($NoPath) {
    Write-Host "  cd `"$Dir`""
    Write-Host "  .\llama.ps1 update           # download the llama.cpp binaries"
} else {
    Write-Host "  Open a NEW terminal, then:"
    Write-Host "  llama update                 # download the llama.cpp binaries"
    Write-Host "  llama serve <alias>          # run a server"
}
