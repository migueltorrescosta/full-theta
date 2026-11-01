"""Fixture tests for tools/lint_spec_cites.py."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import lint_spec_cites  # noqa: E402


def repo(tmp_path: Path, decisions: str, spec: str) -> Path:
    (tmp_path / "docs/spec").mkdir(parents=True)
    (tmp_path / "docs/decisions.md").write_text(decisions)
    (tmp_path / "docs/spec/01-a.md").write_text(spec)
    return tmp_path


# FT: FT-TST-015
def test_flags_a_spec_line_that_misses_the_decision(tmp_path):
    root = repo(
        tmp_path,
        "- D9 Change (owner, FT-AAA-001): x.\n- D10 More (amends FT-AAA-002): y.\n",
        "- **FT-AAA-001** Shall do. (D1)\n- **FT-AAA-002** Shall be. (D10)\n",
    )
    assert lint_spec_cites.run(root) == ["FT-AAA-001: its spec line does not cite D9, which names it"]


# FT: FT-TST-015
def test_citation_must_be_the_whole_number_and_removed_ids_are_skipped(tmp_path):
    root = repo(
        tmp_path,
        "- D1 Change (FT-AAA-001): x.\n- D2 Gone (FT-AAA-002): y.\n",
        "- **FT-AAA-001** Shall. (D11)\n- ~~**FT-AAA-002**~~ Removed (D5).\n",
    )
    assert lint_spec_cites.run(root) == ["FT-AAA-001: its spec line does not cite D1, which names it"]
