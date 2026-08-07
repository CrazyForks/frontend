#!/usr/bin/env python3
"""Small UIAutomator helper for Flutter host-screen navigation."""

from __future__ import annotations

import argparse
import re
import subprocess
import time
import xml.etree.ElementTree as ET


def adb(serial: str, *args: str, check: bool = True) -> str:
    result = subprocess.run(
        ["adb", "-s", serial, *args],
        check=check,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    return result.stdout


def dump(serial: str) -> ET.Element:
    adb(serial, "shell", "uiautomator", "dump", "/sdcard/window.xml", check=False)
    raw = subprocess.check_output(["adb", "-s", serial, "exec-out", "cat", "/sdcard/window.xml"])
    return ET.fromstring(raw)


def node_bounds(node: ET.Element) -> tuple[int, int, int, int]:
    match = re.fullmatch(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", node.attrib["bounds"])
    if not match:
        raise ValueError(f"invalid bounds: {node.attrib.get('bounds')}")
    return tuple(int(value) for value in match.groups())  # type: ignore[return-value]


def find_node(
    root: ET.Element, pattern: str, prefer_clickable: bool = False
) -> ET.Element | None:
    expression = re.compile(pattern, re.IGNORECASE)
    matches = []
    for node in root.iter("node"):
        value = " ".join(
            part
            for part in (node.attrib.get("text", ""), node.attrib.get("content-desc", ""))
            if part
        )
        if expression.search(value):
            matches.append(node)
    if not matches:
        return None
    if prefer_clickable:
        # Labels often repeat between static text and the control that carries
        # them, and document order puts the static copy first: the login page's
        # "Log in to continue" subtitle precedes the "Log in" button. Tapping the
        # static copy silently does nothing, so a click prefers a real target.
        for node in matches:
            if node.attrib.get("clickable") == "true":
                return node
    return matches[0]


def click_pattern(serial: str, pattern: str) -> bool:
    node = find_node(dump(serial), pattern, prefer_clickable=True)
    if node is None:
        return False
    left, top, right, bottom = node_bounds(node)
    adb(serial, "shell", "input", "tap", str((left + right) // 2), str((top + bottom) // 2))
    return True


def wait_pattern(serial: str, pattern: str, timeout: float) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if find_node(dump(serial), pattern) is not None:
            return True
        time.sleep(0.5)
    return False


def find_class_nodes(root: ET.Element, class_name: str) -> list[ET.Element]:
    """Nodes of one widget class, in screen order (top to bottom, left to right)."""
    nodes = [node for node in root.iter("node") if node.attrib.get("class") == class_name]
    return sorted(nodes, key=lambda node: (node_bounds(node)[1], node_bounds(node)[0]))


def click_nth(serial: str, class_name: str, index: int) -> bool:
    nodes = find_class_nodes(dump(serial), class_name)
    if index >= len(nodes):
        return False
    left, top, right, bottom = node_bounds(nodes[index])
    adb(serial, "shell", "input", "tap", str((left + right) // 2), str((top + bottom) // 2))
    return True


def wait_count(serial: str, class_name: str, count: int, timeout: float) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if len(find_class_nodes(dump(serial), class_name)) >= count:
            return True
        time.sleep(0.5)
    return False


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("serial")
    parser.add_argument("action", choices=("click", "wait", "click-nth", "wait-count"))
    parser.add_argument("pattern", help="regex for click/wait, widget class otherwise")
    parser.add_argument("--timeout", type=float, default=20)
    parser.add_argument("--index", type=int, default=0, help="click-nth: 0-based position")
    parser.add_argument("--count", type=int, default=1, help="wait-count: minimum nodes")
    args = parser.parse_args()

    if args.action == "click":
        return 0 if click_pattern(args.serial, args.pattern) else 1
    if args.action == "click-nth":
        return 0 if click_nth(args.serial, args.pattern, args.index) else 1
    if args.action == "wait-count":
        return 0 if wait_count(args.serial, args.pattern, args.count, args.timeout) else 1
    return 0 if wait_pattern(args.serial, args.pattern, args.timeout) else 1


if __name__ == "__main__":
    raise SystemExit(main())
