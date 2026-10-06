from __future__ import annotations

import argparse
import pathlib

from PIL import Image


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--source",
        type=pathlib.Path,
        default=pathlib.Path("website/brand/subscription-vending-source.png"),
    )
    parser.add_argument(
        "--output",
        type=pathlib.Path,
        default=pathlib.Path("website/static/brand"),
    )
    args = parser.parse_args()

    source = Image.open(args.source).convert("RGBA")
    content_bounds = source.getchannel("A").getbbox()
    if content_bounds is None:
        raise ValueError(f"{args.source} has no visible pixels")

    cropped = source.crop(content_bounds)
    padding = max(32, round(max(cropped.size) * 0.055))
    canvas_size = max(cropped.size) + (padding * 2)
    master = Image.new("RGBA", (canvas_size, canvas_size))
    offset = (
        (canvas_size - cropped.width) // 2,
        (canvas_size - cropped.height) // 2,
    )
    master.alpha_composite(cropped, offset)

    args.output.mkdir(parents=True, exist_ok=True)
    favicon_root = args.output.parent / "favicon"
    favicon_root.mkdir(parents=True, exist_ok=True)

    master.save(
        args.output / "subscription-vending-master.png",
        optimize=True,
    )

    outputs = {
        args.output / "subscription-vending-mark-512.png": 512,
        args.output / "subscription-vending-mark-192.png": 192,
        args.output / "subscription-vending-mark-64.png": 64,
        favicon_root / "favicon-32x32.png": 32,
        favicon_root / "favicon-16x16.png": 16,
    }
    for path, size in outputs.items():
        resized = master.resize((size, size), Image.Resampling.LANCZOS)
        resized.save(path, optimize=True)

    print(
        f"Generated {len(outputs) + 1} brand assets from "
        f"{source.width}x{source.height} source artwork."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
