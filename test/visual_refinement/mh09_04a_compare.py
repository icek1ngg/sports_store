"""Derived comparison figures only; original screenshots are never edited."""
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs/features/mh09/artifacts/visual_04a"
REF = ROOT / "docs/features/mh09/artifacts/html_390x844.png"
html = Image.open(REF).convert("RGB")
flutter = Image.open(OUT / "primary_390_top.png").convert("RGB")
assert html.size == flutter.size == (390, 844)
font = ImageFont.truetype(str(ROOT / "assets/fonts/Inter-Variable.ttf"), 13)
figure = Image.new("RGB", (800, 902), "#e5e5e5")
draw = ImageDraw.Draw(figure)
draw.text((6, 5), "HTML: validated mock / Chromium / DPR1", font=font, fill="#111111")
draw.text((410, 5), "Flutter: actual Preview / widget raster / DPR1", font=font, fill="#111111")
draw.text((6, 26), "390 x 844, scale1; different valid business data; no fidelity percentage", font=font, fill="#39393b")
figure.paste(html, (0, 58))
figure.paste(flutter, (410, 58))
figure.save(OUT / "comparison_390.png")

footer = Image.new("RGB", (800, 106), "#e5e5e5")
draw = ImageDraw.Draw(footer)
draw.text((6, 5), "HTML fixed footer: y772, 72px", font=font, fill="#111111")
draw.text((410, 5), "Flutter reserved footer: y772, 72px", font=font, fill="#111111")
footer.paste(html.crop((0, 772, 390, 844)), (0, 34))
footer.paste(flutter.crop((0, 772, 390, 844)), (410, 34))
footer.save(OUT / "comparison_footer.png")

primary = json.loads((OUT / "primary_390.report.json").read_text(encoding="utf-8"))
expected = {
    "header": (0, 0, 390, 64),
    "recipient": (20, 160, 350, 186.5),
    "items": (20, 362.5, 350, 249),
    "payment": (20, 627.5, 350, 289),
    "timeline": (20, 932.5, 350, 414),
}
comparison = []
for name, (x, y, width, height) in expected.items():
    actual = primary["regions"][name]
    comparison.append({"region": name, "html": {"x": x, "y": y, "width": width, "height": height},
                       "flutter": actual, "deltaY": actual["y"] - y,
                       "deltaHeight": actual["height"] - height})
payload = {
    "method": "Geometry from validated HTML manifest/UI_SPEC and actual widget getRect, before scrolling",
    "warning": "Vertical offsets accumulate different contract data/panels. Deltas alone do not classify defects.",
    "regions": comparison, "flutterMainContentHeight": primary["facts"]["mainContentHeight"],
    "independentLifecyclePanelHeight": sum(primary["regions"][name]["height"] for name in ["delivery", "cod", "returns"]),
    "figures": ["comparison_390.png", "comparison_footer.png"],
}
(OUT / "comparison_geometry.json").write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps(payload, ensure_ascii=False))
