# director/

Server-side director: chooses and parameterises scenario components, logs every decision; pure like sim/ (FT-ARC-010).

`RunDriver` is the one interface NetServer drives a run through (`before_tick`, `decisions`, `solo_station`): `Director` (one ship's encounters), `FleetDirector` (a multi-ship session) and `TrainingDriver` (the Shakedown) extend it. Every `Director` plans for a crew faction: a lone ship is a fleet of one, with one budget (D386); a fleet relaunch restarts its plan (D346), rival teams share the taken sites (D348), and LAST_STANDING keeps at most 6 wave raiders alive per ship (D351).

The Shakedown's solo-lesson bots live here too (`TrainingCrew`, `TrainingPartners`, F10): they act only through `ScenarioApi.crew()` (`ApiCrew` verbs), so `director/` still names no `SimWorld`.
