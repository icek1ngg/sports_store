"""Compose existing MH08 screenshots; never alter source evidence."""
import json
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = ROOT / "docs/features/mh08/artifacts"
OUTPUT = ARTIFACTS / "visual_04b2"
SOURCES = [
    ("HTML reference", ARTIFACTS / "html_390x844.png"),
    ("Flutter baseline", OUTPUT / "mh08_04b2_baseline_390x844_s1_top.png"),
    ("Flutter refined", OUTPUT / "mh08_04b2_refined_390x844_s1_top.png"),
]


def main():
    canvas = Image.new("RGB", (390 * 3, 884), "#e5e5e5")
    draw = ImageDraw.Draw(canvas)
    for index, (label, source) in enumerate(SOURCES):
        with Image.open(source) as image:
            assert image.size == (390, 844), (source, image.size)
            canvas.paste(image.convert("RGB"), (index * 390, 40))
        draw.text((index * 390 + 12, 14), label, fill="black")
    canvas.save(OUTPUT / "comparison_390.png")
    baseline = Image.open(SOURCES[1][1]).convert("RGBA")
    refined = Image.open(SOURCES[2][1]).convert("RGBA")
    Image.blend(baseline, refined, 0.5).save(OUTPUT / "overlay_before_after.png")
    measurements = {}
    for phase in ("baseline", "refined"):
        report = json.loads(
            (OUTPUT / f"mh08_04b2_{phase}_report.json").read_text(encoding="utf-8-sig")
        )
        assert not report["failures"], report["failures"]
        measurements[phase] = report["cases"][0]["regions"]
    before = measurements["baseline"]["first_card"]["height"]
    after = measurements["refined"]["first_card"]["height"]
    assert after < before, (before, after)
    measurements["card_height_reduction"] = before - after
    measurements["card_height_reduction_percent"] = round(100 * (before - after) / before, 2)
    (OUTPUT / "density_measurements.json").write_text(
        json.dumps(measurements, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(f"Card: {before:g} -> {after:g}px; reduction {(before-after):g}px")


if __name__ == "__main__":
    main()
