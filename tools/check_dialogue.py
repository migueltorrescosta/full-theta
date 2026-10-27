#!/usr/bin/env python3
"""Dialogue and translation gate (FT-DAT-003, FT-DAT-004, FT-DAT-011).

- Every content/dialogue/*.json validates against its JSON Schema: numbers.json
  against numbers.schema.json, every other file against dialogue.schema.json.
- Line ids are stable keys shared by subtitles, translations and TTS: unique across
  files and prefixed by their file's name (`computer.json` holds `computer.*`).
- Each language's text uses exactly the line's declared slots, and a coalescing key
  only declared slots.
- Every content/conversations/**/*.json validates against conversation.schema.json (FT-DAT-003,
  FT-COM-007); its id is conv.<file name>; every NPC line is a dialogue line, every reply
  text a UI string and every rep a reputation distribution (content/economy/rep/); start
  and next name nodes, option ids are unique per node and every node is reachable.
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


def _intent_ids(root: Path) -> set[str] | None:
    """The IntentTable's ids (input/intent_table.gd), for binding slots; None in a tree without it."""
    table = root / "input/intent_table.gd"
    if not table.is_file():
        return None
    return set(re.findall(r'\{\s*"id":\s*"([a-z0-9_]+)"', table.read_text(encoding="utf-8")))


def _check_binding_slots(line: dict, rel: str, intents: set[str] | None, errors: list[str]) -> None:
    """A binding slot names an IntentTable intent and is text-only (never voiced)."""
    for name, spec in line.get("slots", {}).items():
        if spec == "binding" or (isinstance(spec, dict) and spec.get("kind") == "binding"):
            intent = spec.get("intent") if isinstance(spec, dict) else None
            if intents is not None and intent not in intents:
                errors.append(f"{rel}: {line['id']}: binding slot {name} names no IntentTable intent: {intent}")
        elif isinstance(spec, dict) and "intent" in spec:
            errors.append(f"{rel}: {line['id']}: slot {name}: only a binding slot has an intent")
    kinds = [spec if isinstance(spec, str) else spec.get("kind") for spec in line.get("slots", {}).values()]
    if "binding" in kinds and any(k != "binding" for k in kinds):
        errors.append(f"{rel}: {line['id']}: a binding slot can't share a line with a voiced slot")


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


def _rep_ids(root: Path) -> set[str]:
    ids = set()
    for path in (root / "content/economy/rep").glob("*.tres"):
        m = re.search(r'^id = &"([^"]+)"', path.read_text(encoding="utf-8"), re.M)
        if m:
            ids.add(m.group(1))
    return ids


def _check_conversation(data: dict, rel: str, lines: dict, texts: set, reps: set, errors: list[str]):
    nodes = data["nodes"]
    if data["start"] not in nodes:
        errors.append(f"{rel}: start names no node: {data['start']}")
    reached, todo = set(), [data["start"]]
    while todo:
        name = todo.pop()
        if name in reached or name not in nodes:
            continue
        reached.add(name)
        todo += [o["next"] for o in nodes[name]["options"] if "next" in o]
    for name, node in nodes.items():
        if name not in reached:
            errors.append(f"{rel}: node {name} is unreachable")
        if node["line"] not in lines:
            errors.append(f"{rel}: {name}: unknown dialogue line {node['line']}")
        ids = [o["id"] for o in node["options"]]
        for dup in sorted({i for i in ids if ids.count(i) > 1}):
            errors.append(f"{rel}: {name}: duplicate option id {dup}")
        for option in node["options"]:
            where = f"{rel}: {name}.{option['id']}"
            if option["text"] not in texts:
                errors.append(f"{where}: unknown UI string {option['text']}")
            if "next" in option and option["next"] not in nodes:
                errors.append(f"{where}: next names no node: {option['next']}")
            for effect in option.get("effects", []):
                if "say" in effect and effect["say"] not in lines:
                    errors.append(f"{where}: unknown dialogue line {effect['say']}")
                if "rep" in effect and effect["rep"] not in reps:
                    errors.append(f"{where}: unknown reputation distribution {effect['rep']}")


def _check_conversations(root: Path, lines: dict, errors: list[str]) -> None:
    folder = root / "content/conversations"
    if not folder.is_dir():
        return
    schema = _load(folder / "conversation.schema.json", "content/conversations/conversation.schema.json", errors)
    if schema is None:
        return
    Draft202012Validator.check_schema(schema)
    strings = json.loads((root / "content/i18n/strings.json").read_text(encoding="utf-8"))["strings"]
    reps, seen = _rep_ids(root), {}
    for path in sorted(folder.rglob("*.json")):
        if path.name.endswith(".schema.json"):
            continue
        rel = path.relative_to(root).as_posix()
        data = _load(path, rel, errors)
        if data is None or not _validate(data, schema, rel, errors):
            continue
        if data["id"] != f"conv.{path.stem}":
            errors.append(f"{rel}: id {data['id']} must be conv.{path.stem}")
        if data["id"] in seen:
            errors.append(f"{rel}: duplicate conversation id {data['id']} (also in {seen[data['id']]})")
        seen.setdefault(data["id"], rel)
        _check_conversation(data, rel, lines, set(strings), reps, errors)


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
    intents = _intent_ids(root)
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
            _check_binding_slots(line, rel, intents, errors)
    _check_strings(root, errors)
    _check_conversations(root, seen, errors)
    return errors


def main() -> int:
    errors = run(Path(__file__).resolve().parent.parent)
    for e in errors:
        print(f"dialogue: {e}", file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
