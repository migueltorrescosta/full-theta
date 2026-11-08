# director/

Server-side director: chooses and parameterises scenario components, logs every decision; pure like sim/ (FT-ARC-010).

`RunDriver` is the one interface NetServer drives a run through (`before_tick`, `decisions`, `solo_station`): `Director` (one ship's encounters), `FleetDirector` (a multi-ship session) and `TrainingDriver` (the Shakedown) extend it.

The Shakedown's solo-lesson bots live here too (`TrainingCrew`, `TrainingPartners`, F10): they act only through `ScenarioApi.crew()` (`ApiCrew` verbs), so `director/` still names no `SimWorld`.
