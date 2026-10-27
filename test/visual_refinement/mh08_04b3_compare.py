"""Compose 04B3 evidence and derive Android hit-target metrics offline."""
from __future__ import annotations

import json
import re
import xml.etree.ElementTree as ET
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = ROOT / "docs/features/mh08/artifacts"
OUT = ARTIFACTS / "visual_04b3"
HTML = ARTIFACTS / "html_390x844.png"
WIDGET = ARTIFACTS / "visual_04b2/mh08_04b2_refined_390x844_s1_top.png"
ANDROID = OUT / "android_mh08_initial.png"
INITIAL_XML = OUT / "android_mh08_initial.xml"
PENDING_XML = OUT / "android_pending_card_bottom.xml"
COMPARISON = OUT / "comparison_html_widget_android.png"
METRICS = OUT / "runtime_visual_metrics.json"
BOUNDS = re.compile(r"\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]")
DPR = 440 / 160


def require_files(paths):
    missing = [str(path) for path in paths if not path.is_file()]
    if missing:
        raise FileNotFoundError("Missing evidence: " + ", ".join(missing))


def refuse_overwrite(path):
    if path.exists():
        raise FileExistsError(f"Refusing to overwrite existing evidence: {path}")


def parse_bounds(node):
    match = BOUNDS.fullmatch(node.attrib.get("bounds", ""))
    if not match:
        raise ValueError(f"Invalid Android bounds: {node.attrib.get('bounds')}")
    return tuple(int(value) for value in match.groups())


def find_label(nodes, label):
    matches = [node for node in nodes if node.attrib.get("content-desc") == label or node.attrib.get("text") == label]
    if len(matches) != 1:
        raise ValueError(f"Expected one Android node labelled {label!r}, found {len(matches)}")
    return matches[0]


def target_metric(node, label):
    left, top, right, bottom = parse_bounds(node)
    width, height = right - left, bottom - top
    return {
        "label": label,
        "class": node.attrib.get("class", ""),
        "boundsPx": [left, top, right, bottom],
        "widthPx": width,
        "heightPx": height,
        "widthLogical": round(width / DPR, 2),
        "heightLogical": round(height / DPR, 2),
        "fullyVisible": 0 <= left < right <= 1080 and 136 <= top < bottom <= 2274,
    }


def compose():
    require_files([HTML, WIDGET, ANDROID, INITIAL_XML, PENDING_XML])
    if OUT.parent != ARTIFACTS or OUT.name != "visual_04b3":
        raise ValueError("04B3 outputs must remain in visual_04b3")
    refuse_overwrite(COMPARISON)
    refuse_overwrite(METRICS)
    references = []
    for path in (HTML, WIDGET):
        image = Image.open(path).convert("RGB")
        if image.size != (390, 844):
            raise ValueError(f"Expected 390x844 reference: {path} -> {image.size}")
        references.append(image)
    android = Image.open(ANDROID).convert("RGB")
    if android.size != (1080, 2340):
        raise ValueError(f"Expected 1080x2340 Android capture, got {android.size}")
    scaled_height = round(android.height * 390 / android.width)
    references.append(android.resize((390, scaled_height), Image.Resampling.LANCZOS))
    labels = ["HTML reference 390x844", "Flutter refined MH08 390x844", "Android runtime 1080x2340 -> 390x845"]
    font = ImageFont.truetype(str(ROOT / "assets/fonts/Inter-Variable.ttf"), 14)
    note = "Android includes status bar, navigation bar and DEMO UI; scaled height is 845, so it is not the same 390x844 viewport."
    canvas = Image.new("RGB", (1170, 925), "#e5e5e5")
    draw = ImageDraw.Draw(canvas)
    for index, (label, image) in enumerate(zip(labels, references)):
        x = index * 390
        draw.text((x + 10, 12), label, font=font, fill="#111111")
        canvas.paste(image, (x, 40))
    draw.text((10, 895), note, font=font, fill="#111111")
    canvas.save(COMPARISON)

    initial_nodes = list(ET.parse(INITIAL_XML).getroot().iter("node"))
    pending_nodes = list(ET.parse(PENDING_XML).getroot().iter("node"))
    viewport = parse_bounds(initial_nodes[0])
    if viewport != (0, 0, 1080, 2340):
        raise ValueError(f"Unexpected initial Android viewport: {viewport}")
    reject_node = find_label(pending_nodes, "Từ chối")
    confirm_node = find_label(pending_nodes, "Xác nhận")
    details_node = find_label(pending_nodes, "Xem chi tiết đơn hàng")
    targets = {
        "reject": target_metric(reject_node, "Từ chối"),
        "confirm": target_metric(confirm_node, "Xác nhận"),
        "details": target_metric(details_node, "Xem chi tiết đơn hàng"),
    }
    if any(target["heightPx"] != 132 or target["heightLogical"] != 48.0 for target in targets.values()):
        raise ValueError(f"Expected 132px/48dp action targets: {targets}")
    measurements = {
        "densityDpi": 440,
        "devicePixelRatio": DPR,
        "initialViewportPx": [viewport[2], viewport[3]],
        "sources": {"initialXml": INITIAL_XML.relative_to(ROOT).as_posix(), "pendingCardXml": PENDING_XML.relative_to(ROOT).as_posix()},
        "comparison": {"output": COMPARISON.relative_to(ROOT).as_posix(), "androidIncludes": ["status bar", "navigation bar", "DEMO UI"], "viewportWarning": note},
        "acceptance": {"confirmRejectHeightPx": 132, "confirmRejectHeightLogical": 48.0, "detailsFullWhenBottomScroll": targets["details"]["fullyVisible"]},
        "hitTargets": targets,
    }
    METRICS.write_text(json.dumps(measurements, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"comparison": str(COMPARISON), "metrics": str(METRICS), "actionHeightPx": 132, "actionHeightLogical": 48.0}))


if __name__ == "__main__":
    compose()
