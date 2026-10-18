"""Evidence composition only: different data/renderers prevent a fidelity score."""
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

root = Path(__file__).resolve().parents[2]
out = root / "docs/features/mh08/artifacts/visual_04a"
html = Image.open(out / "html_390x844.png").convert("RGB")
flutter = Image.open(out / "mh08_04a_390_top.png").convert("RGB")
assert html.size == flutter.size == (390, 844)
font = ImageFont.truetype(str(root / "assets/fonts/Inter-Variable.ttf"), 14)
comparison = Image.new("RGB", (800, 880), "#e5e5e5")
draw = ImageDraw.Draw(comparison)
draw.text((10, 9), "HTML / Chromium 390x844", font=font, fill="#111111")
draw.text((410, 9), "Flutter widget render 390x844", font=font, fill="#111111")
comparison.paste(html, (0, 36))
comparison.paste(flutter, (410, 36))
comparison.save(out / "comparison_390.png")
Image.blend(html, flutter, .5).save(out / "overlay_390.png")

html_manifest = json.loads((out / "html_render_manifest.json").read_text(encoding="utf-8"))
flutter_report = json.loads((out / "mh08_04a_reference_report.json").read_text(encoding="utf-8"))
regions = flutter_report["cases"][0]["regions"]
pairs = [
    ("header", html_manifest["header"][0], regions["header"]),
    ("card", html_manifest["cards"][0], regions["card"]),
]
measurements = {
    "viewport": [390, 844],
    "renderer": "Chromium vs Flutter widget render; Inter/Barlow loaded",
    "warning": "Data, contracts and rasterization differ. No pixel-perfect score.",
    "regions": {
        name: {
            "html": reference,
            "flutter": actual,
            "heightDelta": actual["height"] - reference["height"],
            "topDelta": actual["top"] - reference["y"],
        }
        for name, reference, actual in pairs
    },
}
(out / "comparison_metrics.json").write_text(
    json.dumps(measurements, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
)
print(json.dumps({"outputs": ["comparison_390.png", "overlay_390.png"],
                  "cardTopDelta": measurements["regions"]["card"]["topDelta"]}))
