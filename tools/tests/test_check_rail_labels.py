# FT: FT-STN-005
"""Tests for tools/check_rail_labels.py: rail labels fit (C3), help lines are not labels."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import check_rail_labels  # noqa: E402


def test_a_long_label_in_any_language_fails():
    strings = {
        "eng.touch.repair": {"en": "Repair part", "pt_PT": "Reparar peça", "it": "Ripara pezzo"},
        "touch.helm.dock": {"en": "Dock", "pt_PT": "Atracar na estação", "it": "Attracca"},
    }
    errors = check_rail_labels.check(strings)
    assert len(errors) == 1 and errors[0].startswith("touch.helm.dock [pt_PT]")


def test_placeholders_count_as_one_character_and_help_lines_are_not_labels():
    strings = {
        "touch.weapons.mount": {"en": "Mount %d", "pt_PT": "Montagem %d", "it": "Torretta %d"},
        "eng.touch.free": {"en": "Free crew %s12", "pt_PT": "x", "it": "x"},
        "touch.helm.help.turn": {"en": "Turn stick: point the nose", "pt_PT": "x", "it": "x"},
        "help.eng.repair": {"en": "Send the nearest crew to the picked part", "pt_PT": "x", "it": "x"},
    }
    assert check_rail_labels.check(strings) == []
    strings["eng.touch.free"]["en"] = "Free crew %s1234"
    assert len(check_rail_labels.check(strings)) == 1


def test_the_real_rail_labels_are_checked():
    # Every key the check reads is a rail key (the real file is checked in l0).
    assert check_rail_labels.is_rail_key("eng.touch.repair")
    assert check_rail_labels.is_rail_key("weapons.touch_fire_all")
    assert not check_rail_labels.is_rail_key("eng.boost")
