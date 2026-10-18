# 4. Simulation: flight, combat and damage

## 4.1 Flight

Ships fly full 6DOF Newtonian motion: thrust, inertia, momentum and rotation, with ship-specific thruster limits (v0.3 §5, D24). Flight assist is on by default and works by issuing real thruster commands within the ship's limits; decoupled mode turns it off (D24). Thrust consumes propellant; coasting does not (D34). The jump drive moves the ship within the scenario's single global 3D map, between encounter sites, and consumes propellant (D29, D34, D77). Units are SI.

## 4.2 Weapons

Each mount has a position, orientation, firing arc and range on the hull (v0.3 §5). Firing respects arc, range, cooldown, ammunition, energy, heat and subsystem condition. The arsenal covers projectile weapons, energy beams, missiles and torpedoes (v0.3 §5). Weapons aim manually from a claimed mount's turret camera with a lead indicator; controllers get light aim assist (D25, D49). There is no beam/shield frequency matching (D28).

## 4.3 Shields

Shields have one focus direction on the sphere around the ship. Engineering sets total shield power and focus tightness; Helm sets the direction (D16, D48).

## 4.4 Damage and repair

A hit damages the subsystem nearest the impact point (D26). Each subsystem (for example engines, thrusters, weapons, shields, sensors, reactor) takes independent damage with direct consequences (v0.3 §5). Some damage arrives as faults of unknown cause (pair P10). Engineering dispatches repair crews on the cutaway; repairs consume spare parts (D27). Overcharge builds heat; heat past a threshold creates faults (P1, P6). Science reveals weak points and damage-type resistances (D28).

## 4.5 Enemy AI

Basic, testable behaviours first: attack, keep range, retreat at low hull. Later: flanking, coordinated attacks, subsystem targeting and adaptation (v0.3 §5). AI acts only on what its faction's sensors know.

## 4.6 Requirements

- **FT-SIM-001** Ships shall move with 6DOF Newtonian dynamics: forces and torques change linear and angular momentum, with no drag. (v0.3 §5, D24)
- **FT-SIM-002** Each ship definition shall set maximum thrust per local axis, maximum torque per axis, mass and a diagonal inertia tensor. (v0.3 §5)
- **FT-SIM-003** A ship with zero input and assist off shall keep its linear and angular velocity. (D24)
- **FT-SIM-004** Flight assist shall be on by default and shall act only through thruster commands within the ship's current thrust envelope. (D24, v0.3 §5)
- **FT-SIM-005** Helm shall toggle decoupled mode, which disables assist. (D24)
- **FT-SIM-006** The current thrust envelope shall depend on Engineering's power to engines and thrusters, their health and heat. (P1, D50)
- **FT-SIM-007** Thrust, including assist and face-assist thrust, shall consume propellant in proportion to impulse; coasting shall consume none. (D34)
- ~~**FT-SIM-008**~~ Removed (D77): superseded by FT-SIM-034; there are no per-encounter maps.
- **FT-SIM-009** Collisions between ships, asteroids and projectiles shall be detected (projectiles as swept spheres) and shall cause impulse and damage. (D37)
- **FT-SIM-010** Collisions shall be on for all ships, including friendly ships, with a proximity warning before impact. (D37)
- **FT-SIM-011** Each weapon mount shall have a hull position, orientation, firing arc and range, and shall fire only when the aim lies inside its arc. (v0.3 §5)
- **FT-SIM-012** Firing shall respect cooldown, ammunition, energy, heat and mount subsystem condition. (v0.3 §5)
- **FT-SIM-013** The arsenal shall support projectile weapons, energy beams, missiles and torpedoes. (v0.3 §5)
- **FT-SIM-014** Manual aim shall show a lead indicator computed from relative velocity and projectile speed. (D25)
- **FT-SIM-015** Controller aiming shall apply light aim assist; KB/M aiming shall not. (D25)
- **FT-SIM-016** Friendly fire shall be on, with a warning when a shot's path crosses a friendly or neutral ship. (D37)
- **FT-SIM-017** The game shall not use beam or shield frequency matching. (D28)
- **FT-SIM-018** Shields shall have one focus direction, set by Helm, and a total power and focus tightness, set by Engineering. (D16)
- **FT-SIM-019** Damage absorbed by shields shall depend on shield power, focus tightness and the angle between the focus direction and the hit. (D16, P1)
- **FT-SIM-020** A hull hit shall damage the subsystem nearest the impact point. (D26)
- **FT-SIM-021** Each subsystem shall have health, and its effectiveness shall drop with damage in a way defined in data. (v0.3 §5)
- **FT-SIM-022** Weapons shall have damage types, and contacts shall have per-type resistances. (D28)
- **FT-SIM-023** Contacts shall have weak points that, when hit, damage a named subsystem. (D28, P7)
- **FT-SIM-024** Engineering shall repair subsystems by dispatching repair crews to them; each repair shall consume spare parts. (D27)
- **FT-SIM-025** Faults of unknown cause shall repair slowly by default and quickly when the repair names the correct cause. (P10)
- **FT-SIM-026** Overcharging a subsystem shall build heat, and heat past a data-defined threshold shall create a fault. (P1, P6)
- **FT-SIM-027** Enemy AI shall support attack, keep range and retreat at low hull in milestone 1. (v0.3 §5, D72)
- **FT-SIM-028** Enemy AI shall act only on its faction's knowledge. (v0.3 §5, D21)
- **FT-SIM-029** Damage, physics and enemy stats shall never be altered to force an outcome. (v0.3 §5)
- **FT-SIM-030** Every important state change shall emit an event that drives visual and audio feedback on the affected stations. (v0.3 §5)
- **FT-SIM-031** Engineering shall receive an alert when shields fall to 40 %. (v0.3 §5)
- **FT-SIM-032** Stations shall receive a visual warning when the ship is hit or a subsystem they depend on fails. (v0.3 §5)
- **FT-SIM-033** All simulation units shall be SI and documented in the content definitions. (v0.3 §3)
- **FT-SIM-034** The jump drive shall move the ship within the scenario's single global 3D map and shall consume propellant per jump. (D29, D34, D77)
