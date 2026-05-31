# LlamaBox

PowerShell-based manager for llama.cpp Windows releases. No Python or third-party tools required — only what ships with Windows 11. Published at `github.com/Inndy/LlamaBox`.

## Key files

| File | Role |
|------|------|
| `llama.ps1` | Main manager script (the `llama` command). Formerly `llama-manager.ps1`. |
| `llama.cmd` | Launcher so `llama` works once the install dir is on PATH — runs `llama.ps1` via `%~dp0` |
| `install.ps1` | Bootstrap installer/updater — fileless download+extract of the repo, optional PATH add |
| `meta.json` | Installed release state (release tag, dir, cudart_dir, variant). Gitignored. |
| `llama-server.ps1` | Shim — reads meta.json at runtime (committed, not generated) |
| `llama-cli.ps1` | Shim — reads meta.json at runtime (committed, not generated) |
| `start-servers.ps1` | Startup script (committed) — discovers servers/*.txt |
| `llama-server.args.txt` | Default args for single-server interactive use |
| `llama-cli.args.txt` | Default args for llama-cli interactive use |
| `servers/*.txt` | One file per named server instance (started by start-servers.ps1; `example` is skipped) |
| `models/*.txt` | One file per model profile, keyed by filename alias (run via shim or `llama serve <alias>`) |

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
3. If the first arg is not a flag (no leading `-`), treat it as a model profile alias and load `models\<alias>.txt` (error if unknown)
4. Build the final command as: base `.args.txt` → profile args → remaining CLI args (comments and blank lines stripped from files)

The args-file parsing, model-alias resolution, and `cudart_dir` PATH logic are duplicated between the shims and `llama.ps1` (`Get-FileArgs`, `Resolve-ModelArgs`, `Set-CudartPath`) because the shims are standalone entry points — keep them in sync when changing either. `Get-FileArgs` also appears in `start-servers.ps1`, and `Format-ProcessArgs` is shared between `start-servers.ps1` and `llama.ps1`.

## Model profiles

`models/<alias>.txt` holds preferred args per model (subfolder profiles drop the `.args` infix that the root base files keep, so the alias is just the filename stem). Layering is **base args file → profile → extra CLI args**; llama.cpp uses the last value for a repeated flag, so the profile and CLI override base defaults. Invoke via the shim positionally (`.\llama-server.ps1 qwen`), the manager (`.\llama.ps1 serve qwen` / `cli qwen`), or list with `.\llama.ps1 models`. Same file format as any args file.

## Args file format

`Get-FileArgs` is a shell-like tokenizer (per line): tokens split on whitespace, so args may
be one-per-line or several on a line. Lines starting with `#` and blank lines are ignored
(comments are line-level only). `"double quotes"` group values with spaces; `'single quotes'`
group values containing literal double quotes (JSON). Backslashes are always literal, so
unquoted Windows paths survive. Quotes may appear mid-token (shell-style concatenation).

The `models` sub-command prints a table (alias, model source, ctx-size) built by `Get-ModelSummary`, which
reads the `-m`/`--model`, `-hf`/`--hf`, `--hf-repo`/`--hf-file`, and `-c`/`--ctx-size` flags from
each profile; the `example` template is excluded from the listing.

`Format-ProcessArgs` re-quotes space-containing tokens before `Start-Process -ArgumentList`
(used by `Start-AllServers` and `start-servers.ps1`), since PS 5.1 won't re-quote them itself.
The `& $exe @args` splatting path (shims, `Invoke-LlamaExe`) needs no such handling.
