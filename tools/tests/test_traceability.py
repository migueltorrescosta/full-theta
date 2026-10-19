"""Fixture tests for tools/traceability.py."""

import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import traceability  # noqa: E402

BASE = Path(__file__).parent / "fixtures/traceability/base"


def fixture(tmp_path: Path) -> Path:
    root = tmp_path / "repo"
    shutil.copytree(BASE, root)
    assert traceability.run(root, check=False) == []
    return root


# FT: FT-TST-015
def test_map_lists_active_ids_and_excludes_removed(tmp_path):
    root = fixture(tmp_path)
    text = (root / "docs/traceability.md").read_text()
    assert "| FT-AAA-001 | tests | `tests/test_sample.gd`, `tools/tests/check_sample.py` |" in text
    assert "| FT-AAA-002 | tests | `tools/tests/check_sample.py` |" in text
    assert "| FT-AAA-003 | manual | [#7](https://github.com/owner/repo/issues/7) |" in text
    assert "| FT-AAA-005 | pending |" in text
    assert "FT-AAA-004" not in text
    assert traceability.run(root, check=True) == []


# FT: FT-TST-015
def test_check_fails_on_stale_map(tmp_path):
    root = fixture(tmp_path)
    (root / "tests/test_more.gd").write_text("# FT: FT-AAA-005\n")
    assert traceability.run(root, check=True) == [
        "docs/traceability.md is stale: run tools/traceability.py"
    ]


# FT: FT-TST-016
def test_check_fails_on_unknown_id(tmp_path):
    root = fixture(tmp_path)
    (root / "tests/test_more.gd").write_text("# FT: FT-ZZZ-999\n")
    traceability.run(root, check=False)
    assert traceability.run(root, check=True) == ["test tag names unknown id FT-ZZZ-999"]


# FT: FT-TST-016
def test_check_fails_on_removed_id(tmp_path):
    root = fixture(tmp_path)
    (root / "tools/tests/check_more.py").write_text("# FT: FT-AAA-004\n")
    traceability.run(root, check=False)
    assert traceability.run(root, check=True) == ["test tag names removed id FT-AAA-004"]


# FT: FT-TST-016
def test_check_fails_on_empty_tag(tmp_path):
    root = fixture(tmp_path)
    (root / "tests/test_more.gd").write_text("# FT: none\n")
    traceability.run(root, check=False)
    assert traceability.run(root, check=True) == ["tests/test_more.gd: '# FT:' tag names no id"]


# FT: FT-TST-017
def test_check_fails_on_manual_id_without_link(tmp_path):
    root = fixture(tmp_path)
    (root / "docs/traceability-manual.md").write_text("- FT-AAA-005 playtest, no link\n")
    traceability.run(root, check=False)
    assert traceability.run(root, check=True) == [
        "docs/traceability-manual.md: FT-AAA-005 has no issue link"
    ]
