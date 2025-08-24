# Build Windows .exe for the GUI dashboard
# Requires Python + pip installed and available on PATH
# 1) python -m venv .venv; .\.venv\Scripts\Activate.ps1
# 2) pip install -r requirements.txt
# 3) .\build_exe.ps1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$python = Get-Command python -ErrorAction Stop
Write-Host "Using Python: $($python.Source)"

# Ensure dependencies
pip install --upgrade pip
pip install -r requirements.txt

# Build single-file exe
pyinstaller --noconfirm --onefile --windowed --name FastDataRecoveryGUI gui_dashboard.py

Write-Host "Build complete. Find the exe in .\dist\FastDataRecoveryGUI.exe" -ForegroundColor Green

