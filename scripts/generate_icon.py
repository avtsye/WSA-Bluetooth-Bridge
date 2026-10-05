from pathlib import Path
import base64
from io import BytesIO
from PIL import Image

root = Path(__file__).resolve().parents[1]
source_b64 = root / "assets" / "app-icon-original-base64.txt"
png_path = root / "windows-host" / "app-icon.png"
ico_path = root / "windows-host" / "app.ico"

payload = "".join(source_b64.read_text(encoding="utf-8").split())
raw = base64.b64decode(payload, validate=True)
img = Image.open(BytesIO(raw)).convert("RGBA")

if img.width != 256 or img.height != 256:
    raise RuntimeError(f"Unexpected icon source size: {img.size}")

png_path.parent.mkdir(parents=True, exist_ok=True)
img.save(png_path, "PNG", optimize=True)
img.save(
    ico_path,
    format="ICO",
    sizes=[(16,16),(24,24),(32,32),(48,48),(64,64),(128,128),(256,256)],
)

# Re-open the ICO so CI fails immediately if the generated icon is damaged.
check = Image.open(ico_path)
required = {(16,16),(24,24),(32,32),(48,48),(64,64),(128,128),(256,256)}
actual = set(check.info.get("sizes", []))
if not required.issubset(actual):
    raise RuntimeError(f"Generated ICO is missing sizes: {required - actual}")

print(f"Generated exact app icon: {ico_path}")
print(f"ICO sizes: {sorted(actual)}")
