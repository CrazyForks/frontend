#!/usr/bin/env python3
"""Assert the downloader settings switches are flush with the row's content edge.

Why not just compare the two switches to each other (what this script used to do):
both switches can be *equally* wrong. On 2026-08-07 the real defect was that WebF
sized each switch row to its own text instead of to the parent width, so the two
switch right edges fell 145 and 3 device px short of the card edge. A mutual
comparison happens to flag that, but it passes happily whenever both rows are
short by the *same* amount — which is the more likely regression once the rows
are pinned to one width. The row's content edge is the only reference that
actually encodes "pinned to the row end", so that is what we compare against.

The reference comes from the accessibility tree rather than from pixels: the
settings text inputs are published as EditText nodes spanning exactly the row
content box, so their right edge *is* the edge each switch must reach. The
switches themselves are absent from the semantics tree (a WebF <label>+<input>
subtree), so those still have to be located in the screenshot — but only in the
strip to the right of the label text, which removes all the colour guesswork.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import xml.etree.ElementTree as ET
from collections import Counter
from pathlib import Path

from PIL import Image, ImageDraw

# The two switch rows on the downloader settings page, top to bottom.
SWITCH_LABELS = ("嵌入元数据", "播放时自动下载")
BOUNDS_RE = re.compile(r"\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]")


def node_bounds(node: ET.Element) -> tuple[int, int, int, int] | None:
    m = BOUNDS_RE.fullmatch(node.attrib.get("bounds", ""))
    return tuple(int(v) for v in m.groups()) if m else None  # type: ignore[return-value]


def label_text(node: ET.Element) -> str:
    return " ".join(
        p for p in (node.attrib.get("text", ""), node.attrib.get("content-desc", "")) if p
    )


def find_reference(xml_path: Path) -> dict:
    """Row content box (left/right) plus the vertical band holding the switch rows."""
    root = ET.parse(xml_path).getroot()
    nodes = [(n, node_bounds(n)) for n in root.iter("node")]
    nodes = [(n, b) for n, b in nodes if b]

    rows = []
    for name in SWITCH_LABELS:
        hit = next((b for n, b in nodes if name in label_text(n)), None)
        if hit is None:
            raise LookupError(f"switch row label not in semantics tree: {name}")
        rows.append(hit)

    # Every row label starts at the card's content left edge.
    card_left = min(b[0] for b in rows)
    label_right = max(b[2] for b in rows)

    # The text inputs fill the row content box, so their right edge is the target.
    # Restrict to inputs starting at that same left edge: the main page stays
    # mounted behind the settings overlay and its search box is an EditText too.
    edits = [
        b
        for n, b in nodes
        if n.attrib.get("class") == "android.widget.EditText" and abs(b[0] - card_left) <= 3
    ]
    if not edits:
        raise LookupError("no settings EditText to use as the row content edge")
    rights = {b[2] for b in edits}
    if max(rights) - min(rights) > 3:
        raise LookupError(f"settings inputs disagree on the content edge: {sorted(rights)}")

    return {
        "card_left": card_left,
        "label_right": label_right,
        "content_right": max(rights),
        "band_top": min(b[1] for b in rows),
        "band_bottom": max(b[3] for b in rows),
    }


def find_switches(image: Image.Image, ref: dict) -> list[tuple[int, int, int, int]]:
    """Switch pills in the strip right of the label text, within the row band.

    Scanlines are clustered vertically rather than flood-filled into components:
    an "off" switch draws an outlined track with a detached thumb, which is two
    disconnected components inside one pill. Row clustering unions them.

    The band is padded generously because the labels are shorter than the rows
    they sit in — too tight a pad clips the pill and understates its height.
    """
    px = image.convert("RGB")
    w, h = px.size
    x0 = min(w - 1, ref["label_right"] + 4)
    x1 = min(w, ref["content_right"] + 8)
    y0 = max(0, ref["band_top"] - 120)
    y1 = min(h, ref["band_bottom"] + 120)
    if x1 - x0 < 8 or y1 - y0 < 8:
        return []

    # Self-calibrate the background: the modal colour of this strip is the card
    # fill. Beats a hard-coded threshold, which misses a lightly tinted "off" track.
    counts = Counter(px.getpixel((x, y)) for y in range(y0, y1) for x in range(x0, x1))
    bg = counts.most_common(1)[0][0]

    # Per scanline: the horizontal extent of anything that is not the card fill.
    extents: dict[int, tuple[int, int]] = {}
    for y in range(y0, y1):
        xs = [
            x
            for x in range(x0, x1)
            if max(abs(a - b) for a, b in zip(px.getpixel((x, y)), bg)) > 12
        ]
        # A couple of stray antialiasing pixels is not a pill edge.
        if len(xs) >= 4:
            extents[y] = (min(xs), max(xs))

    # Cluster consecutive scanlines; a few blank rows may fall inside one pill
    # (between the track outline and the thumb on the "off" state).
    clusters: list[list[int]] = []
    for y in sorted(extents):
        if clusters and y - clusters[-1][-1] <= 6:
            clusters[-1].append(y)
        else:
            clusters.append([y])

    boxes: list[tuple[int, int, int, int]] = []
    for ys in clusters:
        left = min(extents[y][0] for y in ys)
        right = max(extents[y][1] for y in ys)
        top, bottom = ys[0], ys[-1]
        # A switch pill is wide and tall; card borders are thin, specks are small.
        if right - left >= 100 and bottom - top >= 40:
            boxes.append((left, top, right + 1, bottom + 1))
    return sorted(boxes, key=lambda b: b[1])


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("image", type=Path)
    parser.add_argument(
        "uiautomator", type=Path, help="uiautomator dump of the same screen state"
    )
    parser.add_argument("--expect", type=int, default=len(SWITCH_LABELS))
    args = parser.parse_args()

    image = Image.open(args.image).convert("RGB")
    width, height = image.size
    result: dict = {"image": str(args.image), "size": [width, height]}

    try:
        ref = find_reference(args.uiautomator)
    except (LookupError, ET.ParseError, OSError) as exc:
        result["error"] = f"cannot establish reference edge: {exc}"
        print(json.dumps(result, ensure_ascii=False))
        return 1
    result["reference"] = ref

    boxes = find_switches(image, ref)
    result["switches"] = [
        {"left": b[0], "top": b[1], "right": b[2], "bottom": b[3]} for b in boxes
    ]

    annotated = image.copy()
    draw = ImageDraw.Draw(annotated)
    draw.line(
        [(ref["content_right"], 0), (ref["content_right"], height)],
        fill=(0, 160, 0),
        width=max(2, width // 540),
    )
    for i, b in enumerate(boxes, start=1):
        draw.rectangle(b, outline=(255, 0, 0), width=max(2, width // 360))
        draw.text((b[0], max(0, b[1] - 18)), f"switch {i}", fill=(255, 0, 0))
    annotated.save(args.image.with_name(f"{args.image.stem}-annotated.png"))

    if len(boxes) != args.expect:
        result["error"] = f"expected {args.expect} switches, found {len(boxes)}"
        print(json.dumps(result, ensure_ascii=False))
        return 1

    tolerance = max(3, round(width * 0.004))
    deltas = [ref["content_right"] - b[2] for b in boxes]
    result["tolerance"] = tolerance
    result["right_edge_deltas"] = deltas
    result["passed"] = all(abs(d) <= tolerance for d in deltas)
    print(json.dumps(result, ensure_ascii=False))
    if not result["passed"]:
        print(
            "switches are not flush with the row content edge "
            f"({ref['content_right']}): deltas {deltas}, tolerance {tolerance}",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
