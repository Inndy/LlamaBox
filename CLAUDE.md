# llama-dl

PowerShell-based manager for llama.cpp Windows releases. No Python or third-party tools required — only what ships with Windows 11.

## Key files

| File | Role |
|------|------|
| `llama-manager.ps1` | Main manager script |
| `meta.json` | Installed release state (release tag, dir, cudart_dir, variant) |
| `llama-server.ps1` | Generated shim — reads meta.json at runtime |
| `llama-cli.ps1` | Generated shim — reads meta.json at runtime |
| `start-servers.ps1` | Generated startup script — discovers servers/*.args.txt |
| `llama-server.args.txt` | Default args for single-server interactive use |
| `llama-cli.args.txt` | Default args for llama-cli interactive use |
| `servers/*.args.txt` | One file per named server instance (started by start-servers.ps1) |
| `models/*.args.txt` | One file per model profile, keyed by filename alias (run via shim or `-Model`) |

## Constraints

- **PowerShell 5.1 only** — Windows PowerShell built-in. No PS 7+ syntax: no ternary `?:`, no `??=`, no `ForEach-Object -Parallel`, no `-Environment` on `Start-Process`.
- **No third-party tools** — only built-in .NET (`System.Net.WebClient` for download, `System.IO.Compression` for extraction), `Invoke-RestMethod` (API), standard cmdlets. Downloads are fileless: the asset is buffered in memory and extracted with `ZipArchive` (no temp zip, no `curl.exe`/`tar.exe`).
- Extracted dirs are never deleted on update — old versions stay on disk.

## Variant system

Canonical variants: `cuda12`, `cuda13`, `hip`, `vulkan`, `cpu`
Aliases (resolved before saving to config): `cuda` → `cuda13`, `rocm` → `hip`

CUDA variants (`cuda12`, `cuda13`) also download a separate cudart zip (`cudart-llama-*`) into its own directory. The cudart dir is stored in `meta.json` as `cudart_dir` and prepended to `$env:PATH` by shims and the startup script at runtime.

Asset selection: prefix must be `llama-` (main) or `cudart-llama-` (cudart), matched by variant substring (`-cuda-13.`, `-hip-radeon-`, `-cpu-x64`, etc.), suffix `-x64.zip`.

## Shim design

Shims self-update via `meta.json` — they don't need to be regenerated when the version changes. They:
1. Read `meta.json` to find the current binary dir
2. Prepend `cudart_dir` to `$env:PATH` if present
3. If the first arg is not a flag (no leading `-`), treat it as a model profile alias and load `models\<alias>.args.txt` (error if unknown)
4. Build the final command as: base `.args.txt` → profile args → remaining CLI args (comments and blank lines stripped from files)

The args-file parsing, model-alias resolution, and `cudart_dir` PATH logic are duplicated between the shims and `llama-manager.ps1` (`Get-FileArgs`, `Resolve-ModelArgs`, `Set-CudartPath`) because the shims are standalone entry points — keep them in sync when changing either.

## Model profiles

`models/<alias>.args.txt` holds preferred args per model. Layering is **base args file → profile → extra CLI args**; llama.cpp uses the last value for a repeated flag, so the profile and CLI override base defaults. Invoke via the shim positionally (`.\llama-server.ps1 qwen`), the manager (`-Server -Model qwen` / `-Cli -Model qwen`), or list with `-ListModels`. Same file format as any args file.

## Args file format

One argument per line. Lines starting with `#` and blank lines are ignored. No quoting needed for simple values; use normal PS quoting rules for paths with spaces if passing via CLI.
