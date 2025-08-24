from pathlib import Path
from typing import Optional, BinaryIO

from rich.console import Console
from rich.progress import Progress, BarColumn, TimeElapsedColumn, TimeRemainingColumn, MofNCompleteColumn

console = Console()

# Simple signatures database (expand later)
SIGNATURES: dict[str, dict[str, bytes | int]] = {
    "jpg": {
        "header": bytes.fromhex("FFD8FF"),
        "footer": bytes.fromhex("FFD9"),
        "max_size": 50 * 1024 * 1024,  # 50MB cap to avoid runaways
    },
    "png": {
        "header": bytes.fromhex("89504E470D0A1A0A"),
        "footer": bytes.fromhex("49454E44AE426082"),
        "max_size": 100 * 1024 * 1024,
    },
    "pdf": {
        "header": b"%PDF-",
        "footer": b"%%EOF",
        "max_size": 200 * 1024 * 1024,
    },
    "zip": {
        "header": bytes.fromhex("504B0304"),
        "footer": bytes.fromhex("504B0506"),
        "max_size": 500 * 1024 * 1024,
    },
    # docx, xlsx, pptx are zip-based; carve as zip then classify later
}

CHUNK_SIZE = 1024 * 1024


def _iter_chunks(f: BinaryIO):
    while True:
        data = f.read(CHUNK_SIZE)
        if not data:
            break
        yield data


def carve_stream(in_path: Path, out_dir: Path, types: Optional[list[str]] = None):
    """
    Carve files by signatures from a raw stream (file or disk image).
    """
    types = types or list(SIGNATURES.keys())
    sigs = {k: SIGNATURES[k] for k in types if k in SIGNATURES}

    out_dir.mkdir(parents=True, exist_ok=True)
    file_size = in_path.stat().st_size

    with open(in_path, "rb", buffering=0) as f, Progress(
        "[progress.description]{task.description}",
        BarColumn(),
        MofNCompleteColumn(),
        TimeElapsedColumn(),
        TimeRemainingColumn(),
        transient=False,
        console=console,
    ) as progress:
        task = progress.add_task(f"Scanning {in_path.name}", total=file_size)

        buffer = b""
        offset_base = 0
        found = 0

        for chunk in _iter_chunks(f):
            buffer += chunk
            # Progress
            progress.update(task, advance=len(chunk))

            # Simple header search; could optimize with Aho-Corasick later
            for ftype, sig in sigs.items():
                h: bytes = sig["header"]  # type: ignore[assignment]
                start = 0
                while True:
                    idx = buffer.find(h, start)
                    if idx == -1:
                        break
                    abs_start = offset_base + idx
                    # Try to find footer from there onwards
                    footer: bytes = sig["footer"]  # type: ignore[assignment]
                    max_size: int = sig["max_size"]  # type: ignore[assignment]
                    # Limit search window to prevent OOM
                    search_end = min(len(buffer), idx + max_size)
                    fidx = buffer.find(footer, idx, search_end)
                    # If not found in current buffer, we may need more data; keep only tail.
                    if fidx == -1:
                        # Keep last (max_size) bytes as tail, drop head to keep memory bounded
                        keep_from = max(0, len(buffer) - max_size)
                        offset_base += keep_from
                        buffer = buffer[keep_from:]
                        start = 0
                        break
                    abs_end = offset_base + fidx + len(footer)
                    blob = buffer[idx : fidx + len(footer)]
                    # Write carved file
                    found += 1
                    out_path = out_dir / f"{found:06d}.{ftype}"
                    with open(out_path, "wb") as wf:
                        wf.write(blob)
                    console.print(f"[green]Recovered[/] {ftype.upper()} at offset {abs_start:,} -> {out_path}")
                    # Move past this match
                    start = fidx + len(footer)
            # Trim buffer periodically to keep memory reasonable
            if len(buffer) > 4 * CHUNK_SIZE:
                offset_base += len(buffer) - 2 * CHUNK_SIZE
                buffer = buffer[-2 * CHUNK_SIZE :]

        console.print(f"[bold cyan]Done.[/] Recovered {found} files to {out_dir}")

