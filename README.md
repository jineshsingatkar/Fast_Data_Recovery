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

