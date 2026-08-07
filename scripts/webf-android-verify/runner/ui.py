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


def find_node(root: ET.Element, pattern: str) -> ET.Element | None:
    expression = re.compile(pattern, re.IGNORECASE)
    for node in root.iter("node"):
        value = " ".join(
            part
            for part in (node.attrib.get("text", ""), node.attrib.get("content-desc", ""))
            if part
        )
        if expression.search(value):
            return node
    return None


def click_pattern(serial: str, pattern: str) -> bool:
    node = find_node(dump(serial), pattern)
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


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("serial")
    parser.add_argument("action", choices=("click", "wait"))
    parser.add_argument("pattern")
    parser.add_argument("--timeout", type=float, default=20)
    args = parser.parse_args()

    if args.action == "click":
        return 0 if click_pattern(args.serial, args.pattern) else 1
    return 0 if wait_pattern(args.serial, args.pattern, args.timeout) else 1


if __name__ == "__main__":
    raise SystemExit(main())
