#!/usr/bin/env python3
"""Find the two downloader switches and assert that their right edges align."""

from __future__ import annotations

import argparse
import json
import sys
from collections import deque
from pathlib import Path

from PIL import Image
from PIL import ImageDraw


def components(image: Image.Image) -> list[tuple[int, int, int, int]]:
    pixels = image.convert("RGB")
    width, height = pixels.size
    # The switches are rounded horizontal pills. Keep the threshold broad enough
    # for the purple enabled track and gray disabled outline, while excluding the
    # nearly white card background.
    marked = bytearray(width * height)
    for y in range(height):
        for x in range(width):
            r, g, b = pixels.getpixel((x, y))
            chroma = max(r, g, b) - min(r, g, b)
            dark = max(r, g, b) < 190
            purple = b > r + 12 and b > g + 2 and r < 180
            gray_outline = chroma < 28 and max(r, g, b) < 175
            if dark or purple or gray_outline:
                marked[y * width + x] = 1

    seen = bytearray(width * height)
    found: list[tuple[int, int, int, int]] = []
    for y in range(height):
        for x in range(width):
            index = y * width + x
            if not marked[index] or seen[index]:
                continue
            queue = deque([(x, y)])
            seen[index] = 1
            min_x = max_x = x
            min_y = max_y = y
            size = 0
            while queue:
                cx, cy = queue.popleft()
                size += 1
                min_x = min(min_x, cx)
                max_x = max(max_x, cx)
                min_y = min(min_y, cy)
                max_y = max(max_y, cy)
                for nx, ny in (
                    (cx - 1, cy),
                    (cx + 1, cy),
                    (cx, cy - 1),
                    (cx, cy + 1),
                ):
                    if nx < 0 or nx >= width or ny < 0 or ny >= height:
                        continue
                    ni = ny * width + nx
                    if marked[ni] and not seen[ni]:
                        seen[ni] = 1
                        queue.append((nx, ny))
            box_width = max_x - min_x + 1
            box_height = max_y - min_y + 1
            if size >= 120 and box_width >= 55 and box_width / box_height >= 1.45:
                found.append((min_x, min_y, max_x + 1, max_y + 1))
    return found


def select_switches(boxes: list[tuple[int, int, int, int]], width: int, height: int):
    candidates = [
        box
        for box in boxes
        if 0.25 * height < box[1] < 0.9 * height
        and 1.5 <= (box[2] - box[0]) / (box[3] - box[1]) <= 6
        and 0.12 * width <= box[2] - box[0] <= 0.6 * width
    ]
    # Text strokes can produce several small boxes. The switch tracks are the
    # widest candidates and are separated vertically.
    candidates.sort(key=lambda box: (box[2] - box[0], box[3] - box[1]), reverse=True)
    chosen: list[tuple[int, int, int, int]] = []
    for box in candidates:
        if all(abs(box[1] - other[1]) > box[3] - box[1] for other in chosen):
            chosen.append(box)
        if len(chosen) == 2:
            break
    return sorted(chosen, key=lambda box: box[1])


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("image", type=Path)
    args = parser.parse_args()

    image = Image.open(args.image).convert("RGB")
    width, height = image.size
    boxes = select_switches(components(image), width, height)
    annotated = image.copy()
    drawing = ImageDraw.Draw(annotated)
    for index, box in enumerate(boxes, start=1):
        drawing.rectangle(box, outline=(255, 0, 0), width=max(2, width // 360))
        drawing.text((box[0], max(0, box[1] - 18)), f"switch {index}", fill=(255, 0, 0))
    annotated.save(args.image.with_name(f"{args.image.stem}-annotated.png"))
    result = {
        "image": str(args.image),
        "size": [width, height],
        "switches": [
            {"left": x1, "top": y1, "right": x2, "bottom": y2}
            for x1, y1, x2, y2 in boxes
        ],
    }
    if len(boxes) != 2:
        result["error"] = f"expected 2 switches, found {len(boxes)}"
        print(json.dumps(result, ensure_ascii=False))
        return 1

    right_edges = [box[2] for box in boxes]
    tolerance = max(2, round(width * 0.003))
    result["right_edge_delta"] = abs(right_edges[0] - right_edges[1])
    result["tolerance"] = tolerance
    result["passed"] = result["right_edge_delta"] <= tolerance
    print(json.dumps(result, ensure_ascii=False))
    if not result["passed"]:
        print(
            f"switch right edges are not aligned: {right_edges[0]} vs {right_edges[1]}",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
