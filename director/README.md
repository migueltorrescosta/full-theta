# director/

Server-side director: chooses and parameterises scenario components, logs every decision; pure like sim/ (FT-ARC-010).

`RunDriver` is the one interface NetServer drives a run through (`before_tick`, `decisions`, `solo_station`): `Director` (one ship's encounters), `FleetDirector` (a multi-ship session) and `TrainingDriver` (the Shakedown) extend it.
