@echo off
rem LlamaBox launcher - lets you type `llama ...` from cmd or PowerShell once
rem this folder is on PATH. Resolves llama.ps1 next to this file (%~dp0).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0llama.ps1" %*
