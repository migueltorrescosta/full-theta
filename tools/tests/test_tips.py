# FT: FT-M1-019
"""Tests for tools/tips_shell.py: the real tips pass and the shell's copy is current;
a broken table names what is wrong."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import tips_shell  # noqa: E402


def test_real_tips_pass_and_the_shell_copy_is_current():
    assert tips_shell.check() == []


def test_a_broken_table_names_each_problem():
    data = tips_shell.load()
    data["tips"] = data["tips"][:3] + [
        {"id": "x.1", "topic": "nowhere", "en": "Hi", "pt_PT": "Olá", "it": ""},
        {"id": "x.1", "topic": "helm", "en": "a" * 200, "pt_PT": "b", "it": "c"},
    ]
    errors = tips_shell.errors_in(data)
    assert "x.1: unknown topic nowhere" in errors
    assert "x.1: no it text" in errors
    assert "x.1: duplicate id" in errors
    assert any(e.startswith("x.1: en text is 200 characters") for e in errors)
    assert any(e.startswith("5 tips (at least") for e in errors)
    assert any(e.startswith("weapons: ") for e in errors)


def test_rewrite_replaces_only_the_line_between_the_markers():
    html = "a\n" + tips_shell.BEGIN + "\nold\n" + tips_shell.END + "\nb"
    assert tips_shell.rewrite(html, "new") == "a\n" + tips_shell.BEGIN + "\nnew\n" + tips_shell.END + "\nb"
