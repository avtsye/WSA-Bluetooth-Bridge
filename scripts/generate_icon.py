from pathlib import Path
import base64
from io import BytesIO
from PIL import Image

root = Path(__file__).resolve().parents[1]
source_b64 = root / "assets" / "app-icon-base64.txt"
png_path = root / "windows-host" / "app-icon.png"
ico_path = root / "windows-host" / "app.ico"

payload = "".join(source_b64.read_text(encoding="utf-8").split())
payload += "=" * (-len(payload) % 4)
raw = base64.b64decode(payload, validate=True)
img = Image.open(BytesIO(raw)).convert("RGBA")
if img.width < 128 or img.height < 128:
    raise RuntimeError(f"Icon source is unexpectedly small: {img.size}")

png_path.parent.mkdir(parents=True, exist_ok=True)
img.save(png_path, "PNG", optimize=True)

# Keep the exact generated artwork and derive all Windows icon sizes from it.
icon_source = img.resize((256, 256), Image.Resampling.LANCZOS)
icon_source.save(
    ico_path,
    format="ICO",
    sizes=[(16,16),(24,24),(32,32),(48,48),(64,64),(128,128),(256,256)],
)

print(f"Generated {png_path}")
print(f"Generated {ico_path}")
