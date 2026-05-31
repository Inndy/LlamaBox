$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$metaFile = "$dir\meta.json"
if (-not (Test-Path $metaFile)) {
    throw "llama.cpp is not installed. Run llama-manager.ps1 to install."
}
$meta = Get-Content $metaFile -Raw | ConvertFrom-Json
if ($meta.cudart_dir) {
    $env:PATH = "$dir\$($meta.cudart_dir);$env:PATH"
}
$exe = "$dir\$($meta.dir)\llama-server.exe"

function Get-FileArgs($path) {
    if (Test-Path $path) {
        return @(Get-Content $path |
            Where-Object { $_ -notmatch '^\s*#' -and $_.Trim() -ne '' })
    }
    return @()
}

$passArgs  = @($args)
$modelArgs = @()
# A leading token that is not a flag (no '-') is treated as a model profile alias.
if ($passArgs.Count -gt 0 -and $passArgs[0] -notmatch '^-') {
    $alias = $passArgs[0]
    $profileFile = "$dir\models\$alias.args.txt"
    if (-not (Test-Path $profileFile)) {
        $available = @(Get-ChildItem "$dir\models\*.args.txt" -ErrorAction SilentlyContinue |
            ForEach-Object { $_.BaseName })
        throw "Unknown model profile '$alias'. Available: $($available -join ', ')"
    }
    $modelArgs = Get-FileArgs $profileFile
    $passArgs  = @($passArgs | Select-Object -Skip 1)
}

$baseArgs = Get-FileArgs "$dir\llama-server.args.txt"
& $exe @baseArgs @modelArgs @passArgs
