# LlamaBox

A self-contained PowerShell manager for [llama.cpp](https://github.com/ggml-org/llama.cpp) on Windows. It downloads and updates official releases, ships ready-to-use shim scripts, manages per-model argument profiles, and runs multiple `llama-server` instances as a startup service.

**Requirements:** Windows 10/11 with Windows PowerShell 5.1 (built-in). No Python, no admin rights, no third-party tools — only what ships with Windows.

## Install

One line in PowerShell installs LlamaBox to `%LOCALAPPDATA%\LlamaBox` and adds it to your user `PATH`:

```powershell
irm https://raw.githubusercontent.com/Inndy/LlamaBox/main/install.ps1 | iex
```

To choose the directory or skip the `PATH` change, pass arguments via a script block:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/Inndy/LlamaBox/main/install.ps1))) -Dir D:\LlamaBox -NoPath
```

Re-running the installer upgrades the scripts in place and leaves your argument files (`llama-*.args.txt`, `models/`, `servers/`) and `meta.json` untouched.

Prefer to do it by hand? Just download or `git clone` the repo into a folder — every script self-locates, so the folder can live anywhere.

Once the install directory is on `PATH` (open a **new** terminal afterwards), the `llama` command works from anywhere thanks to the bundled `llama.cmd` launcher:

```powershell
llama update                  # download/update the llama.cpp binaries
llama serve qwen              # run a server with the qwen profile
llama models                  # list your model profiles
```

> The examples below use `.\llama.ps1`, which works from inside the install folder. If you put the
> folder on `PATH` (the installer does this by default), replace `.\llama.ps1` with `llama` and run
> it from anywhere.

## Quick start

```powershell
.\llama.ps1 update
```

Running `.\llama.ps1` with no arguments prints the available sub-commands.

On first run, `update` will:
- Download the latest llama.cpp release (CUDA 13 by default) straight into memory (fileless, no temp zip)
- Extract it in-memory with .NET `ZipArchive`
- Download the CUDA runtime DLLs into a separate directory (CUDA variants only)
- Create default argument files (`llama-server.args.txt`, `llama-cli.args.txt`) and example profiles under `servers/` and `models/` if they don't exist yet

The shims (`llama-server.ps1`, `llama-cli.ps1`) and `start-servers.ps1` ship with LlamaBox — they read `meta.json` at runtime, so they never need regenerating after an update.

## Variants

```powershell
.\llama.ps1 update cuda13   # NVIDIA CUDA 13.x (default)
.\llama.ps1 update cuda12   # NVIDIA CUDA 12.x
.\llama.ps1 update hip      # AMD ROCm/HIP (Radeon)
.\llama.ps1 update vulkan   # Vulkan (cross-vendor)
.\llama.ps1 update cpu      # CPU-only (no GPU runtime)

# Aliases
.\llama.ps1 update cuda     # same as cuda13
.\llama.ps1 update rocm     # same as hip
```

The chosen variant is saved to `meta.json` and reused on subsequent runs.

## Updating

Re-run `update` at any time. It checks the latest GitHub release and downloads only if a newer version is available or the variant changed.

```powershell
.\llama.ps1 update
```

Old extracted directories are kept on disk. Only `meta.json` is updated to point at the new version.

## Using the shims

Edit the args files to set your model path and options, then run the shims:

**`llama-server.args.txt`**
```
--model C:\models\mistral-7b-q4_k_m.gguf
--port 8080
--ctx-size 4096
```

```powershell
.\llama-server.ps1              # uses args from llama-server.args.txt
.\llama-server.ps1 --threads 8  # extra args are appended after file args
```

The shims automatically resolve the correct binary path and prepend the CUDA runtime directory to `PATH` (for CUDA variants) at runtime — no changes needed after an update.

## Args file format

Every arguments file — the base `llama-server.args.txt` / `llama-cli.args.txt` and the per-server / per-model `.txt` profiles — is parsed the same way:

- Arguments are split on whitespace, so you can put one per line **or** several on a line.
- Lines that are blank or start with `#` are ignored (comments are line-level only).
- Use `"double quotes"` for values containing spaces, e.g. a Windows path:
  `--model "C:\Program Files\models\m.gguf"`.
- Use `'single quotes'` for values that themselves contain double quotes, e.g. JSON:
  `--chat-template-kwargs '{"reasoning_effort":"medium"}'`.
- Backslashes are literal, so unquoted Windows paths like `C:\models\m.gguf` work as-is.

> Note: when launching via `start-servers.ps1` (which uses `Start-Process`), a value that
> contains *both* a space and a double quote is a Windows PowerShell 5.1 edge case and may not
> be passed intact; the shims (`llama-server.ps1` / `llama-cli.ps1`) are unaffected.

## Model profiles

Keep your preferred args per model in `models/<alias>.txt`, then launch by alias:

```powershell
.\llama-server.ps1 qwen                # base args + models\qwen.txt
.\llama-cli.ps1    qwen -p "hello"     # works for the CLI too
.\llama-server.ps1 qwen --port 9000    # CLI args still override
```

**`models\qwen.txt`**
```
# Qwen2.5 7B - my preferred setup
--model C:\models\qwen2.5-7b-q4_k_m.gguf
--ctx-size 8192
--n-gpu-layers 99
```

The first argument is treated as a profile alias only when it does **not** start with `-` (every llama flag does), so it never collides with normal args. Effective arguments are layered as **base args file → profile → extra CLI args**, and llama.cpp lets later values win — so put shared defaults (e.g. `--port`) in `llama-server.args.txt` and per-model settings in the profile. Running with no alias keeps the old behavior (base args file only).

List defined profiles (a table of alias, model source, and context size; the `example`
template is omitted):

```powershell
.\llama.ps1 models
```

The manager takes a profile alias positionally, just like the shims:

```powershell
.\llama.ps1 serve qwen
.\llama.ps1 cli qwen -p "hello"
```

## Running multiple servers

Create one `.txt` file per server instance in the `servers/` directory:

```
servers\
  mistral.txt
  llava.txt
  codellama.txt
```

Each file follows the same format as `llama-server.args.txt`. A file named `example.txt` is
skipped, so the shipped template never auto-starts. Then run:

```powershell
.\start-servers.ps1
```

This launches all configured servers as hidden background processes.

## Running at startup

Place `start-servers.ps1` (or a shortcut to it) in your Windows Startup folder:

```
shell:startup
```

Or open it directly with Win+R → `shell:startup`.

## Directory layout

```
LlamaBox\
  llama.ps1                            ← main manager (the `llama` command)
  llama.cmd                            ← launcher so `llama` works on PATH
  install.ps1                          ← installer / script updater
  meta.json                            ← installed-release state (created by update)
  llama-server.ps1                     ← shim
  llama-cli.ps1                        ← shim
  start-servers.ps1                    ← starts every servers\*.txt instance (except example)
  llama-server.args.txt
  llama-cli.args.txt
  servers\
    example.txt
  models\
    example.txt                        ← per-model arg profiles (run by alias)
  llama-b8676-bin-win-cuda-13.1-x64\   ← binaries (downloaded by update)
  cudart-llama-bin-win-cuda-13.1-x64\  ← CUDA runtime DLLs (cuda variants only)
```

## License

[MIT](LICENSE)
