$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$metaFile = "$dir\meta.json"
if (-not (Test-Path $metaFile)) {
    throw "llama.cpp is not installed. Run 'llama update' to install."
}
$meta = Get-Content $metaFile -Raw | ConvertFrom-Json
if ($meta.cudart_dir) {
    $env:PATH = "$dir\$($meta.cudart_dir);$env:PATH"
}
$exe = "$dir\$($meta.dir)\llama-cli.exe"

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

$passArgs  = @($args)
$modelArgs = @()
# A leading token that is not a flag (no '-') is treated as a model profile alias.
if ($passArgs.Count -gt 0 -and $passArgs[0] -notmatch '^-') {
    $alias = $passArgs[0]
    $profileFile = "$dir\models\$alias.txt"
    if (-not (Test-Path $profileFile)) {
        $available = @(Get-ChildItem "$dir\models\*.txt" -ErrorAction SilentlyContinue |
            ForEach-Object { $_.BaseName })
        throw "Unknown model profile '$alias'. Available: $($available -join ', ')"
    }
    $modelArgs = Get-FileArgs $profileFile
    $passArgs  = @($passArgs | Select-Object -Skip 1)
}

$baseArgs = Get-FileArgs "$dir\llama-cli.args.txt"
& $exe @baseArgs @modelArgs @passArgs
