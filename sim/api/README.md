# sim/api/

The Scenario API: the only part of `sim/` that `director/` and `scenarios/` may name. It hands out ids and value copies and turns writes into queued sim commands (FT-ARC-016, FT-DAT-009, D103).

`ApiCrew` (`ScenarioApi.crew()`) is the one write seam for scripted crewmen: verbs such as `aim_at`, `repair_next`, `pip_up` and `press_next` that submit real crew commands, which the solo-lesson bots of `director/` act through. `CrewMoves` holds the moves it shares with the bot batch.
