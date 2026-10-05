from pathlib import Path
import cairosvg
from PIL import Image

root = Path(__file__).resolve().parents[1]
svg_path = root / "assets" / "app-icon.svg"
png_path = root / "windows-host" / "app-icon.png"
ico_path = root / "windows-host" / "app.ico"

png_path.parent.mkdir(parents=True, exist_ok=True)

cairosvg.svg2png(
    url=str(svg_path),
    write_to=str(png_path),
    output_width=1024,
    output_height=1024,
)

img = Image.open(png_path).convert("RGBA")
img.save(
    ico_path,
    format="ICO",
    sizes=[(16,16),(24,24),(32,32),(48,48),(64,64),(128,128),(256,256)],
)

print(f"Generated {ico_path}")
