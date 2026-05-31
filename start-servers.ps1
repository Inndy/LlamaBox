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

Get-ChildItem "$dir\servers\*.args.txt" -ErrorAction SilentlyContinue | ForEach-Object {
    $name = $_.BaseName
    $fileArgs = @(Get-Content $_.FullName |
        Where-Object { $_ -notmatch '^\s*#' -and $_.Trim() -ne '' })
    Write-Host "Starting $name..."
    Start-Process -FilePath $exe -ArgumentList $fileArgs -WindowStyle Hidden
}
