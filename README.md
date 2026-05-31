# llama-dl

A self-contained PowerShell manager for [llama.cpp](https://github.com/ggml-org/llama.cpp) on Windows. Downloads and updates releases, creates shim scripts, and manages multiple llama-server instances as a startup service.

**Requirements:** Windows 10/11 with PowerShell 5.1 (built-in). No Python, no admin rights, no third-party tools.

## Quick start

```powershell
.\llama-manager.ps1 -Update
```

Running `.\llama-manager.ps1` with no arguments prints the available sub-commands.

On first run `-Update` will:
- Download the latest llama.cpp release (CUDA 13 by default) straight into memory (fileless, no temp zip)
- Extract it in-memory with .NET `ZipArchive`
- Download the CUDA runtime DLLs into a separate directory
- Create `llama-server.ps1` and `llama-cli.ps1` shims
- Create `llama-server.args.txt` and `llama-cli.args.txt` for persistent arguments
- Create a `servers/` directory with an example server config
- Generate `start-servers.ps1` for running all servers at boot

## Variants

```powershell
.\llama-manager.ps1 -Variant cuda13   # NVIDIA CUDA 13.x (default)
.\llama-manager.ps1 -Variant cuda12   # NVIDIA CUDA 12.x
.\llama-manager.ps1 -Variant hip      # AMD ROCm/HIP (Radeon)
.\llama-manager.ps1 -Variant vulkan   # Vulkan (cross-vendor)
.\llama-manager.ps1 -Variant cpu      # CPU-only (no GPU runtime)

# Aliases
.\llama-manager.ps1 -Variant cuda     # same as cuda13
.\llama-manager.ps1 -Variant rocm     # same as hip
```

The chosen variant is saved to `meta.json` and reused on subsequent runs.

## Updating

Re-run `-Update` at any time. It checks the latest GitHub release and downloads only if a newer version is available or the variant changed.

```powershell
.\llama-manager.ps1 -Update
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

Every `*.args.txt` file (base, server, and model profiles) is parsed the same way:

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

Keep your preferred args per model in `models/<alias>.args.txt`, then launch by alias:

```powershell
.\llama-server.ps1 qwen                # base args + models\qwen.args.txt
.\llama-cli.ps1    qwen -p "hello"     # works for the CLI too
.\llama-server.ps1 qwen --port 9000    # CLI args still override
```

**`models\qwen.args.txt`**
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
.\llama-manager.ps1 -ListModels
```

The manager accepts a profile too, via `-Model`:

```powershell
.\llama-manager.ps1 -Server -Model qwen
.\llama-manager.ps1 -Cli -Model qwen -p "hello"
```

## Running multiple servers

Create one `.args.txt` file per server instance in the `servers/` directory:

```
servers\
  mistral.args.txt
  llava.args.txt
  codellama.args.txt
```

Each file follows the same format as `llama-server.args.txt`. Then run:

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
llama-dl\
  llama-manager.ps1
  meta.json
  llama-server.ps1
  llama-cli.ps1
  llama-server.args.txt
  llama-cli.args.txt
  start-servers.ps1
  servers\
    example.args.txt
  models\
    example.args.txt                   ← per-model arg profiles (run by alias)
  llama-b8676-bin-win-cuda-13.1-x64\   ← binaries
  cudart-llama-bin-win-cuda-13.1-x64\  ← CUDA runtime DLLs (cuda variants only)
```
