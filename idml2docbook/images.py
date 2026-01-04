import os
import sys
import subprocess
import tempfile
from pathlib import Path
from psd_tools import PSDImage
from PIL import Image
import shutil

RASTER_EXTS = [".tif", ".tiff", ".png", ".jpg", ".jpeg", ".psd"]
VECTOR_EXTS = [".svg", ".eps", ".ai", ".pdf"]

from utils import custom_slugify

def detect_imagemagick_command():
    """
    Detect which ImageMagick executable is available.
    Returns ("magick", "convert") or ("convert", None) or ("mogrify", None).
    """
    # Preferred order: ImageMagick 7+ (magick), then convert, then mogrify
    for cmd in ["magick", "convert", "mogrify"]:
        if shutil.which(cmd):
            # If 'magick' exists, we must call 'magick convert' internally
            if cmd == "magick":
                return ("magick", "convert")
            else:
                return (cmd, None)
    raise EnvironmentError(
        "❌ ImageMagick not found. Please install it and ensure 'magick', 'convert', or 'mogrify' is in PATH."
    )

def flatten_psd(input_path: Path, output_path: Path):
    """Flatten a PSD into a single PNG."""
    psd = PSDImage.open(input_path)
    composite = psd.composite()
    composite.save(output_path, format="PNG")
    return output_path

def flatten_tif(input_path: Path, output_path: Path):
    """Flatten a multi-layer TIFF into a single PNG."""
    with Image.open(input_path) as img:
        if getattr(img, "n_frames", 1) > 1:
            img.seek(0)
        img = img.convert("RGB")
        img.save(output_path, format="PNG")
    return output_path

def process_images(input_dir, resize="900x"): # , colorspace="Gray"):
    input_dir = Path(input_dir)
    if not input_dir.is_dir():
        print(f"Error: '{input_dir}' is not a valid directory.")
        return

    output_dir = input_dir / "processed_images"
    output_dir.mkdir(exist_ok=True)

    magick_cmd, subcmd = detect_imagemagick_command()

    print(f"📁 Scanning directory: {input_dir}")
    print(f"📂 Output directory: {output_dir}")

    with tempfile.TemporaryDirectory() as tmpdir:
        tmpdir = Path(tmpdir)
        processed = 0

        for file_path in input_dir.iterdir():
            if not file_path.is_file():
                continue

            ext = file_path.suffix.lower()
            if ext not in RASTER_EXTS:
                continue

            slug_base = custom_slugify(file_path.stem, length=100)
            temp_input = file_path

            # Handle PSD/TIFF flattening
            if ext == ".psd":
                temp_input = tmpdir / f"{slug_base}.png"
                flatten_psd(file_path, temp_input)
            elif ext in (".tif", ".tiff"):
                temp_input = tmpdir / f"{slug_base}.png"
                flatten_tif(file_path, temp_input)

            output_path = output_dir / f"{slug_base}.jpg"

            # Build command
            if subcmd:  # e.g., magick convert
                cmd = [magick_cmd, subcmd]
            else:  # e.g., convert or mogrify
                cmd = [magick_cmd]

            cmd += [
                str(temp_input),
                "-resize", resize,
                # "-colorspace", colorspace,
                str(output_path)
            ]

            try:
                subprocess.run(cmd, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                print(f"✅ {file_path.name} → {output_path.name}")
                processed += 1
            except subprocess.CalledProcessError as e:
                print(f"❌ Failed to process {file_path.name}: {e.stderr.decode().strip()}")

    if processed == 0:
        print("⚠️ No matching images found.")
    else:
        print(f"\n✨ Done! {processed} images saved in '{output_dir}'")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python process_images.py <input-folder>")
        sys.exit(1)

    process_images(sys.argv[1])
