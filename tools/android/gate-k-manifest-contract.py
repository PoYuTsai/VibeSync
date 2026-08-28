#!/usr/bin/env python3
"""Fail-closed static contract check for the disposable Gate K manifest."""

from __future__ import annotations

import sys
import xml.etree.ElementTree as ET
from pathlib import Path


ANDROID_NS = "http://schemas.android.com/apk/res/android"
ANDROID_NAME = f"{{{ANDROID_NS}}}name"
ANDROID_MAX_SDK = f"{{{ANDROID_NS}}}maxSdkVersion"
ANDROID_PERMISSION = f"{{{ANDROID_NS}}}permission"
ANDROID_EXPORTED = f"{{{ANDROID_NS}}}exported"

EXPECTED_PERMISSIONS = {
    "android.permission.READ_MEDIA_IMAGES": None,
    "android.permission.READ_MEDIA_VISUAL_USER_SELECTED": None,
    "android.permission.READ_EXTERNAL_STORAGE": "32",
}


def fail(message: str) -> None:
    raise SystemExit(f"Gate K manifest contract failed: {message}")


def main() -> int:
    manifest_path = Path(
        sys.argv[1]
        if len(sys.argv) == 2
        else "android/gate-k-prototype/src/main/AndroidManifest.xml"
    )
    if not manifest_path.is_file():
        fail(f"manifest not found: {manifest_path}")

    try:
        root = ET.fromstring(manifest_path.read_text(encoding="utf-8"))
    except (OSError, ET.ParseError) as error:
        fail(f"manifest is not readable XML: {error}")

    permission_nodes = root.findall("uses-permission")
    if len(permission_nodes) != len(EXPECTED_PERMISSIONS):
        fail(f"expected exactly {len(EXPECTED_PERMISSIONS)} permissions")
    actual_permissions = {
        node.get(ANDROID_NAME): node.get(ANDROID_MAX_SDK) for node in permission_nodes
    }
    if actual_permissions != EXPECTED_PERMISSIONS:
        fail(f"permission allowlist mismatch: {actual_permissions!r}")

    serialized = manifest_path.read_text(encoding="utf-8")
    for forbidden in ("AccessibilityService", "BIND_ACCESSIBILITY_SERVICE", "MANAGE_EXTERNAL_STORAGE"):
        if forbidden in serialized:
            fail(f"forbidden privacy capability present: {forbidden}")

    application = root.find("application")
    if application is None:
        fail("application is missing")
    services = application.findall("service")
    if len(services) != 1:
        fail(f"expected exactly one service, got {len(services)}")
    service = services[0]
    if service.get(ANDROID_NAME) != ".GateKPrototypeInputMethodService":
        fail("unexpected service name")
    if service.get(ANDROID_PERMISSION) != "android.permission.BIND_INPUT_METHOD":
        fail("service must bind only to BIND_INPUT_METHOD")
    if service.get(ANDROID_EXPORTED) != "true":
        fail("IME service must be exported for system binding")

    actions = {
        action.get(ANDROID_NAME)
        for action in service.findall("intent-filter/action")
    }
    if actions != {"android.view.InputMethod"}:
        fail(f"unexpected service actions: {actions!r}")

    print("Gate K manifest contract: PASS (static allowlist; not a Play approval)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
