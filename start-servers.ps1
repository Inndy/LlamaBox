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

Get-ChildItem "$dir\servers\*.args.txt" -ErrorAction SilentlyContinue | ForEach-Object {
    $name = $_.BaseName
    $fileArgs = Get-FileArgs $_.FullName
    Write-Host "Starting $name..."
    Start-Process -FilePath $exe -ArgumentList (Format-ProcessArgs $fileArgs) -WindowStyle Hidden
}
