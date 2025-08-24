from pathlib import Path
from typing import Optional

import typer
from rich.console import Console

from .carver import carve_stream

app = typer.Typer(help="RecoveryPro - fast signature-based carving (MVP)")
console = Console()


@app.command(name="quick-carve")
def quick_carve(
    source: Path = typer.Argument(..., help="Path to a source image/file (e.g., .dd/.img or any large file)"),
    out_dir: Path = typer.Option(Path("./recovered"), "--out", "-o", help="Destination folder"),
    types: Optional[str] = typer.Option(None, "--types", "-t", help="Comma list (e.g., jpg,png,pdf)"),
):
    """
    MVP: Carve by signatures from a source file or disk image (safe read-only).
    """
    if not source.exists():
        raise typer.BadParameter(f"Source not found: {source}")
    selected = [t.strip().lower() for t in types.split(",")] if types else None
    carve_stream(source, out_dir, selected)


@app.command()
def version():
    console.print("RecoveryPro MVP 0.1.0")


def main():
    app()


if __name__ == "__main__":
    main()

