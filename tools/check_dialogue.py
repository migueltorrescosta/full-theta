#!/usr/bin/env python3
"""Dialogue and translation gate (FT-DAT-003, FT-DAT-004, FT-DAT-011).

- Every content/dialogue/*.json validates against its JSON Schema: numbers.json
  against numbers.schema.json, every other file against dialogue.schema.json.
- Line ids are stable keys shared by subtitles, translations and TTS: unique across
  files and prefixed by their file's name (`computer.json` holds `computer.*`).
- Each language's text uses exactly the line's declared slots, and a coalescing key
  only declared slots.
- Translation completeness: every line, number table and UI string
  (content/i18n/*.json) has non-blank text in each launch language.

Prints one message per problem and exits 1 on any.
"""

import json
import re
import sys
from pathlib import Path

from jsonschema import Draft202012Validator

LANGS = ("en", "pt_PT", "it")
SLOT = re.compile(r"\{([^{}]*)\}")
SLOT_NAME = re.compile(r"^[a-z][a-z0-9_]*$")
SCHEMAS = {"numbers.json": "numbers.schema.json"}
DEFAULT_SCHEMA = "dialogue.schema.json"


def _load(path: Path, rel: str, errors: list[str]):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        errors.append(f"{rel}: not valid JSON ({e})")
        return None


def _validate(data, schema: dict, rel: str, errors: list[str]) -> bool:
    found = sorted(Draft202012Validator(schema).iter_errors(data), key=lambda e: list(e.path))
    for e in found:
        where = "/".join(str(p) for p in e.path) or "(root)"
        errors.append(f"{rel}: {where}: {e.message}")
    return not found


def _check_line(line: dict, rel: str, stem: str, seen: dict, errors: list[str]) -> None:
    lid = line["id"]
    if lid in seen:
        errors.append(f"{rel}: duplicate line id {lid} (also in {seen[lid]})")
    seen.setdefault(lid, rel)
    if lid.split(".", 1)[0] != stem:
        errors.append(f"{rel}: line id {lid} must start with '{stem}.'")
    declared = set(line.get("slots", {}))
    for lang in LANGS:
        text = line["text"][lang]
        used = SLOT.findall(text)
        bad = [s for s in used if not SLOT_NAME.match(s)]
        rest = SLOT.sub("", text)
        if bad or "{" in rest or "}" in rest:
            errors.append(f"{rel}: {lid}: {lang}: malformed slot in {text!r}")
        if set(used) != declared or len(used) != len(set(used)):
            errors.append(
                f"{rel}: {lid}: {lang}: slots {sorted(used)} don't match the declared {sorted(declared)}"
            )
        if not text.strip():
            errors.append(f"{rel}: {lid}: {lang}: blank text")
    unknown = set(SLOT.findall(line.get("coalesce", ""))) - declared
    if unknown:
        errors.append(f"{rel}: {lid}: coalesce uses undeclared slots {sorted(unknown)}")


def _check_strings(root: Path, errors: list[str]) -> None:
    for path in sorted((root / "content/i18n").glob("*.json")):
        rel = path.relative_to(root).as_posix()
        data = _load(path, rel, errors)
        if data is None:
            continue
        strings = data.get("strings") if isinstance(data, dict) else None
        if not isinstance(strings, dict):
            errors.append(f"{rel}: needs a 'strings' object")
            continue
        for key, texts in strings.items():
            if not isinstance(texts, dict):
                errors.append(f"{rel}: {key}: needs text per language")
                continue
            for lang in LANGS:
                if not str(texts.get(lang, "")).strip():
                    errors.append(f"{rel}: {key}: missing {lang}")
            extra = set(texts) - set(LANGS)
            if extra:
                errors.append(f"{rel}: {key}: unknown languages {sorted(extra)}")


def run(root: Path) -> list[str]:
    errors: list[str] = []
    folder = root / "content/dialogue"
    schemas = {}
    for name in {DEFAULT_SCHEMA, *SCHEMAS.values()}:
        schema = _load(folder / name, f"content/dialogue/{name}", errors)
        if schema is not None:
            Draft202012Validator.check_schema(schema)
            schemas[name] = schema
    if errors:
        return errors
    seen: dict[str, str] = {}
    files = [p for p in sorted(folder.glob("*.json")) if not p.name.endswith(".schema.json")]
    if not any(p.name not in SCHEMAS for p in files):
        errors.append("content/dialogue: no dialogue files")
    for path in files:
        rel = path.relative_to(root).as_posix()
        data = _load(path, rel, errors)
        if data is None:
            continue
        if not _validate(data, schemas[SCHEMAS.get(path.name, DEFAULT_SCHEMA)], rel, errors):
            continue
        if path.name in SCHEMAS:
            continue
        for line in data["lines"]:
            _check_line(line, rel, path.stem, seen, errors)
    _check_strings(root, errors)
    return errors


def main() -> int:
    errors = run(Path(__file__).resolve().parent.parent)
    for e in errors:
        print(f"dialogue: {e}", file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
