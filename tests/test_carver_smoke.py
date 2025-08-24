import os
import sys
import subprocess
from pathlib import Path


def test_smoke_import():
    # Ensure the package can be imported and has a main
    import recoverypro
    assert hasattr(recoverypro, "main")


def test_quick_carve_cli_help(tmp_path: Path):
    # Use the current interpreter to ensure we run inside the venv
    proc = subprocess.run([sys.executable, "-m", "recoverypro", "--help"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    assert proc.returncode == 0

