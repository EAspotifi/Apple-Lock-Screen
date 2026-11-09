#!/usr/bin/env python3
"""Build the DMS registry entry for Apple Lock Auth.

The file this writes is the manifest that goes in
duxlabs-dev/dux-plugin-registry under plugins/. That is what makes the
plugin show up in Settings -> Plugins instead of "not in registry".
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SEMVER = re.compile(r"^\d+\.\d+\.\d+(-[a-zA-Z0-9.-]+)?(\+[a-zA-Z0-9.-]+)?$")
CATEGORIES = {
    "utilities",
    "monitoring",
    "system",
    "appearance",
    "productivity",
    "media",
    "networking",
}
PLUGIN_FIELDS = ("id", "name", "description", "version", "author", "capabilities")


def fail(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def load_json(path: Path) -> dict:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        fail(f"missing {path.relative_to(ROOT)}")
    except json.JSONDecodeError as exc:
        fail(f"{path.relative_to(ROOT)} is not valid JSON: {exc}")
    if not isinstance(data, dict):
        fail(f"{path.relative_to(ROOT)} must contain an object")
    return data


def require_text(data: dict, field: str, source: str) -> str:
    value = data.get(field)
    if not isinstance(value, str) or not value.strip():
        fail(f"{source} {field} must be a nonempty string")
    return value


def repo_url(explicit: str) -> str:
    if explicit.strip():
        return explicit.strip().rstrip("/")
    repository = os.environ.get("GITHUB_REPOSITORY", "").strip()
    server = os.environ.get("GITHUB_SERVER_URL", "https://github.com").rstrip("/")
    if repository:
        return f"{server}/{repository}"
    fail("pass --repo or run this inside GitHub Actions")


def owner_slug(explicit: str, url: str) -> str:
    raw = explicit.strip() or os.environ.get("GITHUB_REPOSITORY_OWNER", "")
    if not raw and url.startswith("https://github.com/"):
        raw = url.removeprefix("https://github.com/").split("/", 1)[0]
    slug = re.sub(r"[^a-z0-9]+", "-", raw.lower()).strip("-")
    if not slug:
        fail("could not derive a GitHub owner for the registry filename")
    return slug


def validate_plugin(plugin: dict) -> None:
    for field in PLUGIN_FIELDS:
        if field == "capabilities":
            continue
        require_text(plugin, field, "plugin.json")
    if not SEMVER.fullmatch(plugin["version"]):
        fail(f"plugin.json version must be X.Y.Z, got {plugin['version']!r}")
    capabilities = plugin.get("capabilities")
    if not isinstance(capabilities, list) or not capabilities or not all(
        isinstance(item, str) and item.strip() for item in capabilities
    ):
        fail("plugin.json capabilities must be a nonempty list of strings")
    if "components" not in plugin and "component" not in plugin:
        fail("plugin.json needs component or components")
    for field in ("component", "settings"):
        if field in plugin:
            check_qml(plugin[field], field)
    components = plugin.get("components", {})
    if components is not None:
        if not isinstance(components, dict):
            fail("plugin.json components must be an object")
        for name, rel in components.items():
            check_qml(rel, f"components.{name}")


def check_qml(value: object, field: str) -> None:
    if not isinstance(value, str) or not value.startswith("./") or not value.endswith(".qml"):
        fail(f"plugin.json {field} must be a relative .qml path")
    path = (ROOT / value.removeprefix("./")).resolve()
    if not path.is_relative_to(ROOT) or not path.is_file():
        fail(f"plugin.json {field} does not point at a file: {value}")


def build_entry(plugin: dict, registry: dict, url: str) -> dict:
    category = require_text(registry, "category", "registry.json")
    if category not in CATEGORIES:
        fail(f"registry.json category must be one of {', '.join(sorted(CATEGORIES))}")
    for field in ("dependencies", "compositors", "distro"):
        values = registry.get(field)
        if not isinstance(values, list) or not all(isinstance(item, str) for item in values):
            fail(f"registry.json {field} must be a list of strings")
    entry = {
        "id": plugin["id"],
        "name": plugin["name"],
        "capabilities": plugin["capabilities"],
        "category": category,
        "repo": url,
        "author": plugin["author"],
        "description": plugin["description"],
        "dependencies": registry["dependencies"],
        "compositors": registry["compositors"],
        "distro": registry["distro"],
    }
    requires = plugin.get("requires_dms")
    if isinstance(requires, str) and requires.strip():
        entry["requires_dms"] = requires
    return entry


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default="", help="Public git URL of this plugin")
    parser.add_argument("--owner", default="", help="GitHub owner used in the filename")
    parser.add_argument("--out", default="dist", help="Directory for the registry JSON")
    args = parser.parse_args()

    plugin = load_json(ROOT / "plugin.json")
    registry = load_json(ROOT / "registry.json")
    validate_plugin(plugin)
    url = repo_url(args.repo)
    entry = build_entry(plugin, registry, url)
    slug = owner_slug(args.owner, url)
    out_dir = Path(args.out)
    if not out_dir.is_absolute():
        out_dir = ROOT / out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    destination = out_dir / f"{slug}-apple-lock-auth.json"
    destination.write_text(json.dumps(entry, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(destination)


if __name__ == "__main__":
    main()
