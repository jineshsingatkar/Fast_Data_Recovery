# RecoveryPro - Fast Data Recovery (MVP)

This is the initial scaffold for a Python-based data recovery tool focused on:
- Quick signature-based carving for common file types (JPG/PNG/PDF/ZIP)
- A clean CLI using Typer and rich progress bars
- Safe, read-only scanning from a source image or file

How to use

1) Activate the virtual environment
- Windows PowerShell:
  .\.venv\Scripts\Activate.ps1

2) Run the CLI
- Show help:
  python -m recoverypro --help
- Quick carve example:
  python -m recoverypro quick-carve path\to\image.dd -o .\recovered -t jpg,png,pdf

Project layout
- src/recoverypro/cli.py     -> Main CLI entry point
- src/recoverypro/carver.py  -> Signature-based carving logic
- src/recoverypro/__init__.py
- tests/test_carver_smoke.py -> Basic smoke test for the carver logic

Notes
- This MVP is a starting point. We will expand with NTFS/MFT recovery, previews/filters, reports, and packaging to .exe using PyInstaller.

## CLI Dashboards (Windows + Linux)

This project also includes a cross-platform, menu-driven dashboard to help you run safe data recovery operations.

Files:
- FastDataRecovery.ps1 — Windows PowerShell dashboard
- FastDataRecovery.sh — Linux Bash dashboard

Safety first
- Image failing drives first (ddrescue on Linux) and recover from the image.
- Only run repair tools after the data is secured.

Quick start (Windows)
- Open PowerShell as Administrator.
- Temporarily allow scripts in this session:
  Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
- Run the dashboard:
  .\FastDataRecovery.ps1

Quick start (Linux)
- Make executable and run as root:
  chmod +x FastDataRecovery.sh
  sudo ./FastDataRecovery.sh

Requirements
Windows:
- smartmontools (smartctl) for SMART checks (e.g. choco install smartmontools)
- TestDisk/PhotoRec: place testdisk_win.exe and photorec_win.exe in this folder or install via package

Linux (Debian/Ubuntu):
- sudo apt update && sudo apt install -y gddrescue testdisk photorec smartmontools ntfs-3g exfatprogs e2fsprogs xfsprogs btrfs-progs kpartx util-linux

Outputs
- Reports are written to ./reports
- Temporary logs under ./logs

GUI Dashboard (.exe and cross-platform)
- Run directly with Python:
  python gui_dashboard.py
- Build a Windows .exe:
  1) python -m venv .venv; .\.venv\Scripts\Activate.ps1
  2) pip install -r requirements.txt
  3) .\build_exe.ps1
- After building, launch ./dist/FastDataRecoveryGUI.exe

GUI notes
- The GUI provides four tiles matching the requested categories:
  Deleted Recovery, Complete Recovery (guided), Lost Partition Recovery, Digital Media Recovery.
- It launches TestDisk/PhotoRec if present. On Windows, place testdisk_win.exe and photorec_win.exe beside the exe or add to PATH.
- Use SMART to assess health before recovery; image failing drives first.

