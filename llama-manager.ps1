[CmdletBinding(DefaultParameterSetName = 'Help')]
param(
    [Parameter(ParameterSetName = 'Update')]
    [switch]$Update,

    [Parameter(ParameterSetName = 'Update')]
    [ValidateSet('cuda12', 'cuda13', 'cuda', 'hip', 'rocm', 'vulkan', 'cpu')]
    [string]$Variant,

    [Parameter(ParameterSetName = 'Server')]
    [switch]$Server,

    [Parameter(ParameterSetName = 'Cli')]
    [switch]$Cli,

    [Parameter(ParameterSetName = 'StartServers')]
    [switch]$StartServers,

    [Parameter(ParameterSetName = 'ListModels')]
    [switch]$ListModels,

    [Parameter(ParameterSetName = 'Help')]
    [switch]$Help,

    [Parameter(ParameterSetName = 'Server')]
    [Parameter(ParameterSetName = 'Cli')]
    [string]$Model,

    [Parameter(ParameterSetName = 'Server', ValueFromRemainingArguments = $true)]
    [Parameter(ParameterSetName = 'Cli',    ValueFromRemainingArguments = $true)]
    [string[]]$ExtraArgs
)

$ErrorActionPreference = 'Stop'

$BaseDir    = Split-Path -Parent $MyInvocation.MyCommand.Path
$MetaFile   = "$BaseDir\meta.json"
$ServersDir = "$BaseDir\servers"
$ModelsDir  = "$BaseDir\models"

$VariantAliases = @{
    cuda = 'cuda13'
    rocm = 'hip'
}

$VariantPatterns = @{
    cuda12 = '-cuda-12.'
    cuda13 = '-cuda-13.'
    hip    = '-hip-radeon-'
    vulkan = '-vulkan-'
    cpu    = '-cpu-x64'
}

$CudaVariants = @('cuda12', 'cuda13')

function Read-JsonFile($path) {
    if (Test-Path $path) {
        return Get-Content $path -Raw | ConvertFrom-Json
    }
    return $null
}

function Write-JsonFile($path, $obj) {
    $obj | ConvertTo-Json -Depth 5 | Set-Content $path -Encoding UTF8
}

function Get-LatestRelease($variantKey) {
    $pattern = $VariantPatterns[$variantKey]
    $release = Invoke-RestMethod `
        -Uri 'https://api.github.com/repos/ggml-org/llama.cpp/releases/latest' `
        -Headers @{ Accept = 'application/vnd.github+json' }

    $tag   = $release.tag_name
    $asset = $release.assets | Where-Object {
        $_.name -like 'llama-*' -and $_.name -like "*$pattern*" -and $_.name -like '*-x64.zip'
    } | Select-Object -First 1

    if ($null -eq $asset) {
        throw "No asset found for variant '$variantKey' in release $tag"
    }

    $result = @{
        Tag        = $tag
        Name       = $asset.name
        Url        = $asset.browser_download_url
        Size       = $asset.size
        CudartName = $null
        CudartUrl  = $null
        CudartSize = $null
    }

    if ($CudaVariants -contains $variantKey) {
        $cudart = $release.assets | Where-Object {
            $_.name -like 'cudart-llama-*' -and $_.name -like "*$pattern*" -and $_.name -like '*-x64.zip'
        } | Select-Object -First 1

        if ($null -eq $cudart) {
            Write-Warning "No cudart asset found for variant '$variantKey' in release $tag"
        } else {
            $result.CudartName = $cudart.name
            $result.CudartUrl  = $cudart.browser_download_url
            $result.CudartSize = $cudart.size
        }
    }

    return $result
}

function Get-AssetStream($url, $size, $label) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add('User-Agent', 'llama-dl')

    $total = [long]$size
    # ZipArchive needs random access (the central directory is at the end),
    # so buffer the whole download in memory rather than streaming to disk.
    $ms = New-Object System.IO.MemoryStream
    if ($total -gt 0 -and $total -lt 2GB) { $ms.Capacity = [int]$total }

    $src = $null
    try {
        $src  = $wc.OpenRead($url)
        $buf  = New-Object byte[] (1MB)
        $done = [long]0
        $tick = 0
        while (($n = $src.Read($buf, 0, $buf.Length)) -gt 0) {
            $ms.Write($buf, 0, $n)
            $done += $n
            if (($tick++ % 16) -eq 0 -and $total -gt 0) {
                Write-Progress -Activity "Downloading $label" `
                    -Status "$($done -shr 20) / $($total -shr 20) MB" `
                    -PercentComplete ([math]::Min(100, $done * 100 / $total))
            }
        }
    } finally {
        if ($src) { $src.Dispose() }
        $wc.Dispose()
        Write-Progress -Activity "Downloading $label" -Completed
    }

    $ms.Position = 0
    return $ms
}

function Install-Asset($assetInfo) {
    $name    = $assetInfo.Name
    $sizeMB  = [math]::Round($assetInfo.Size / 1MB, 1)
    $dirName = $name -replace '\.zip$', ''
    $destDir = "$BaseDir\$dirName"

    if (Test-Path $destDir) {
        Write-Host "Already extracted: $dirName"
        return $dirName
    }

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    Write-Host "Downloading $name ($sizeMB MB)..."
    $ms = Get-AssetStream $assetInfo.Url $assetInfo.Size $name

    Write-Host "Extracting..."
    $null = New-Item -ItemType Directory -Path $destDir -Force
    $zip = New-Object System.IO.Compression.ZipArchive($ms, [System.IO.Compression.ZipArchiveMode]::Read)
    try {
        [System.IO.Compression.ZipFileExtensions]::ExtractToDirectory($zip, $destDir)
    } catch {
        Remove-Item $destDir -Recurse -Force -ErrorAction SilentlyContinue
        throw
    } finally {
        $zip.Dispose()
        $ms.Dispose()
    }

    Write-Host "Installed: $dirName"
    return $dirName
}

function Set-CudartPath($meta) {
    if ($meta.cudart_dir) {
        $env:PATH = "$BaseDir\$($meta.cudart_dir);$env:PATH"
    }
}

function Get-FileArgs($path) {
    if (-not (Test-Path $path)) { return @() }
    $tokens = New-Object System.Collections.Generic.List[string]
    foreach ($line in Get-Content $path) {
        if ($line -match '^\s*#' -or $line.Trim() -eq '') { continue }
        $cur = New-Object System.Text.StringBuilder
        $started = $false
        $quote = $null
        foreach ($c in $line.ToCharArray()) {
            if ($quote) {
                if ($c -eq $quote) { $quote = $null } else { [void]$cur.Append($c) }
            } elseif ($c -eq '"' -or $c -eq "'") {
                $quote = $c; $started = $true
            } elseif ($c -eq ' ' -or $c -eq "`t") {
                if ($started) {
                    $tokens.Add($cur.ToString())
                    $cur = New-Object System.Text.StringBuilder
                    $started = $false
                }
            } else {
                [void]$cur.Append($c); $started = $true
            }
        }
        if ($started) { $tokens.Add($cur.ToString()) }
    }
    return @($tokens.ToArray())
}

function Format-ProcessArgs($a) {
    return @($a | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } })
}

function Get-ModelAliases {
    return @(Get-ChildItem "$ModelsDir\*.args.txt" -ErrorAction SilentlyContinue |
        ForEach-Object { $_.BaseName })
}

function Get-ModelSummary($alias) {
    $a = Get-FileArgs "$ModelsDir\$alias.args.txt"
    $model = $null; $hf = $null; $hfRepo = $null; $hfFile = $null; $ctx = $null
    for ($i = 0; $i -lt $a.Count; $i++) {
        switch ($a[$i]) {
            { $_ -in '-m', '--model' }    { $model  = $a[$i + 1] }
            { $_ -in '-hf', '--hf' }      { $hf     = $a[$i + 1] }
            '--hf-repo'                   { $hfRepo = $a[$i + 1] }
            '--hf-file'                   { $hfFile = $a[$i + 1] }
            { $_ -in '-c', '--ctx-size' } { $ctx    = $a[$i + 1] }
        }
    }
    $source = if ($model)      { Split-Path -Leaf $model }
              elseif ($hf)     { $hf }
              elseif ($hfRepo) { "$hfRepo$(if ($hfFile) { " / $hfFile" })" }
              else             { '(no model defined)' }
    return [PSCustomObject]@{ Alias = $alias; Model = $source; Ctx = $ctx }
}

function Resolve-ModelArgs($modelAlias) {
    if (-not $modelAlias) { return @() }
    $profileFile = "$ModelsDir\$modelAlias.args.txt"
    if (-not (Test-Path $profileFile)) {
        throw "Unknown model profile '$modelAlias'. Available: $((Get-ModelAliases) -join ', ')"
    }
    return Get-FileArgs $profileFile
}

function Invoke-LlamaExe($exeName, $argsFileName, $modelAlias, $extraArgs) {
    $meta = Read-JsonFile $MetaFile
    if ($null -eq $meta) { throw "llama.cpp is not installed. Run llama-manager.ps1 to install." }

    Set-CudartPath $meta

    $exe       = "$BaseDir\$($meta.dir)\$exeName"
    $baseArgs  = Get-FileArgs "$BaseDir\$argsFileName"
    $modelArgs = Resolve-ModelArgs $modelAlias

    $extra = if ($extraArgs) { $extraArgs } else { @() }
    & $exe @baseArgs @modelArgs @extra
}

function Start-AllServers {
    $meta = Read-JsonFile $MetaFile
    if ($null -eq $meta) { throw "llama.cpp is not installed. Run llama-manager.ps1 to install." }

    Set-CudartPath $meta

    $exe = "$BaseDir\$($meta.dir)\llama-server.exe"
    Get-ChildItem "$ServersDir\*.args.txt" -ErrorAction SilentlyContinue | ForEach-Object {
        $name     = $_.BaseName
        $fileArgs = Get-FileArgs $_.FullName
        Write-Host "Starting $name..."
        Start-Process -FilePath $exe -ArgumentList (Format-ProcessArgs $fileArgs) -WindowStyle Hidden
    }
}

function Initialize-ArgsFiles {
    if (-not (Test-Path "$BaseDir\llama-server.args.txt")) {
        Set-Content "$BaseDir\llama-server.args.txt" @'
# llama-server arguments - one per line, # lines are ignored
# --model C:\models\model.gguf
# --port 8080
# --ctx-size 4096
'@ -Encoding UTF8
    }

    if (-not (Test-Path "$BaseDir\llama-cli.args.txt")) {
        Set-Content "$BaseDir\llama-cli.args.txt" @'
# llama-cli arguments - one per line, # lines are ignored
# --model C:\models\model.gguf
# --ctx-size 4096
'@ -Encoding UTF8
    }

    $null = New-Item -ItemType Directory -Path $ServersDir -Force

    $existingCount = (Get-ChildItem "$ServersDir\*.args.txt" -ErrorAction SilentlyContinue |
        Measure-Object).Count
    if ($existingCount -eq 0) {
        Set-Content "$ServersDir\example.args.txt" @'
# Example server instance - copy and rename this file for each server
# --model C:\models\mistral-7b-q4.gguf
# --port 8080
# --ctx-size 4096
'@ -Encoding UTF8
        Write-Host "Created: servers\example.args.txt"
    }

    $null = New-Item -ItemType Directory -Path $ModelsDir -Force

    $existingModels = (Get-ChildItem "$ModelsDir\*.args.txt" -ErrorAction SilentlyContinue |
        Measure-Object).Count
    if ($existingModels -eq 0) {
        Set-Content "$ModelsDir\example.args.txt" @'
# Model profile - copy and rename to an alias, e.g. models\qwen.args.txt
# Run with:  .\llama-server.ps1 qwen   (or .\llama-cli.ps1 qwen)
# Appended after llama-server.args.txt / llama-cli.args.txt - profile values win.
#
# Multiple args may share a line. Use "double quotes" for paths with spaces and
# 'single quotes' for values that contain double quotes (e.g. JSON). Backslashes
# are literal. Lines starting with # and blank lines are ignored.
# --model "C:\models\qwen2.5-7b-q4_k_m.gguf"
# --ctx-size 8192
# --n-gpu-layers 99
# --chat-template-kwargs '{"reasoning_effort":"medium"}'
'@ -Encoding UTF8
        Write-Host "Created: models\example.args.txt"
    }
}

function Invoke-Update {
    $meta = Read-JsonFile $MetaFile

    $variantKey = 'cuda13'
    if ($Variant) {
        $variantKey = if ($VariantAliases.ContainsKey($Variant)) { $VariantAliases[$Variant] } else { $Variant }
        Write-Host "Variant set to: $variantKey$(if ($variantKey -ne $Variant) { " (alias: $Variant)" })"
    } elseif ($meta -and $meta.variant) {
        $variantKey = $meta.variant
    }

    Write-Host "Checking latest release (variant: $variantKey)..."
    $assetInfo = Get-LatestRelease $variantKey
    $tag = $assetInfo.Tag
    Write-Host "Latest release: $tag"

    $needsInstall = $null -eq $meta -or $meta.release -ne $tag -or $meta.variant -ne $variantKey
    $needsCudart  = $assetInfo.CudartUrl -and ($needsInstall -or -not $meta.cudart_dir)

    if ($needsInstall -or $needsCudart) {
        $dirName = if ($needsInstall) { Install-Asset $assetInfo } else { $meta.dir }

        $cudartDirName = ''
        if ($assetInfo.CudartUrl) {
            $cudartDirName = Install-Asset @{
                Name = $assetInfo.CudartName
                Url  = $assetInfo.CudartUrl
                Size = $assetInfo.CudartSize
            }
        }

        Write-JsonFile $MetaFile ([PSCustomObject]@{
            release    = $tag
            dir        = $dirName
            cudart_dir = $cudartDirName
            variant    = $variantKey
            updated_at = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        })
    } else {
        Write-Host "Already up to date: $tag ($variantKey)"
    }

    Initialize-ArgsFiles
}

function Show-Help {
    Write-Host @'
llama-manager.ps1 - manage llama.cpp Windows releases

USAGE:
  .\llama-manager.ps1 -Update [-Variant <variant>]      Download/install or update llama.cpp to the latest release
  .\llama-manager.ps1 -Server [-Model <alias>] [args]   Run llama-server
  .\llama-manager.ps1 -Cli [-Model <alias>] [args]      Run llama-cli
  .\llama-manager.ps1 -StartServers                     Start every servers\*.args.txt instance
  .\llama-manager.ps1 -ListModels                       List available model profiles
  .\llama-manager.ps1 -Help                             Show this help

VARIANTS:
  cuda12, cuda13, cuda (-> cuda13), hip, rocm (-> hip), vulkan, cpu
  Default: cuda13, or the previously installed variant if one exists.
'@
}

#
# Main
#

switch ($PSCmdlet.ParameterSetName) {
    'Server'       { Invoke-LlamaExe 'llama-server.exe' 'llama-server.args.txt' $Model $ExtraArgs; break }
    'Cli'          { Invoke-LlamaExe 'llama-cli.exe'    'llama-cli.args.txt'    $Model $ExtraArgs; break }
    'StartServers' { Start-AllServers; break }
    'ListModels'   {
        $aliases = @(Get-ModelAliases | Where-Object { $_ -ne 'example' })
        if ($aliases) {
            $aliases | ForEach-Object { Get-ModelSummary $_ } | Format-Table -AutoSize
        } else {
            Write-Host "No model profiles found. Add files to $ModelsDir"
        }
        break
    }
    'Update'       { Invoke-Update; break }
    default        { Show-Help; break }
}
