class_name S5World
extends RefCounted
## The prototype's whole simulation: one ship, one moving target (H2), one free mark
## (Bravo) and a station (F1). Steps at a fixed 60 Hz (FT-ARC-006); the caller owns the
## accumulator (S5FixedStep). Pure, so tests drive it tick by tick.

const DT: float = 1.0 / 60.0
const TARGET: int = 0
const MARK: int = 1
const STATION: int = 2
## Ship at rest within these limits ends all-stop (m/s, rad/s).
const STOP_SPEED: float = 0.05
const STOP_RATE: float = 0.002
const LEVEL_DONE: float = deg_to_rad(0.3)

var ship: S5ShipBody = S5ShipBody.new()
var helm: S5HelmState = S5HelmState.new()
var assist: S5Assist = S5Assist.new()
var items: Array[S5Item] = []
var time: float = 0.0
var tick: int = 0
var last_command: S5ThrustCommand = S5ThrustCommand.new()
var propellant_used: float = 0.0

# Target script: straight line plus a sideways weave (provisional).
var target_start: Vector3 = Vector3(-3000.0, 1500.0, -4500.0)
var target_velocity: Vector3 = Vector3(110.0, 0.0, 30.0)
var target_weave: Vector3 = Vector3(0.0, 120.0, 120.0)
var target_weave_period: float = 30.0


func _init() -> void:
	items.append(S5Item.make("H2", S5Item.Kind.CONTACT, Vector3.ZERO))
	items.append(S5Item.make("Bravo", S5Item.Kind.MARK, Vector3(4000.0, -800.0, -6000.0)))
	items.append(S5Item.make("F1", S5Item.Kind.CONTACT, Vector3(-1500.0, -400.0, 2500.0)))
	_move_target()


func selected_item() -> S5Item:
	return items[helm.selected]


## Moves the free mark (FT-SPA-014: a mark free in world space).
func place_mark(pos: Vector3) -> void:
	items[MARK].position = pos


## Advances one fixed tick under Helm's intent.
func step(input: S5HelmInput) -> void:
	_apply_edges(input)
	if input.has_manual_input(assist.input_dead_zone) or input.approach or input.face:
		helm.all_stop = false
	if absf(input.pitch) > assist.input_dead_zone or absf(input.yaw) > assist.input_dead_zone:
		helm.level = S5HelmState.Level.OFF
	if absf(input.roll) > assist.input_dead_zone:
		helm.level = S5HelmState.Level.OFF
	if not helm.decoupled and not input.approach:
		helm.throttle_setpoint = clampf(
			helm.throttle_setpoint + input.throttle * assist.throttle_ramp * DT,
			-assist.max_reverse,
			assist.max_speed
		)
	if helm.approaching and not input.approach:
		# Releasing approach hands control back at the current speed (FT-SIM-037).
		helm.throttle_setpoint = _forward_speed()
	helm.approaching = input.approach

	last_command = assist.command(ship, helm, input, selected_item())
	propellant_used += S5Integrator.step(ship, last_command.force, last_command.torque, DT)
	tick += 1
	time = tick * DT
	# After the tick, so the target is at the same time as the ship.
	_move_target()

	if (
		helm.all_stop
		and ship.velocity.length() < STOP_SPEED
		and ship.angular_velocity.length() < STOP_RATE
	):
		helm.all_stop = false
	if helm.level != S5HelmState.Level.OFF and assist.level_error(ship, helm.level) < LEVEL_DONE:
		if ship.angular_velocity.length() < 0.01:
			helm.level = S5HelmState.Level.OFF


func _apply_edges(input: S5HelmInput) -> void:
	if input.decoupled_pressed:
		helm.decoupled = not helm.decoupled
		if not helm.decoupled:
			# Back to assist: hold the current speed instead of lurching to the old one.
			helm.throttle_setpoint = _forward_speed()
	if input.select_pressed:
		helm.selected = (helm.selected + 1) % items.size()
	if input.all_stop_pressed:
		helm.all_stop = true
		helm.throttle_setpoint = 0.0
		helm.level = S5HelmState.Level.OFF
	if input.level_pressed:
		# First press rolls; a second press, or one when already rolled level, also
		# pitches onto the ecliptic (FT-HLM-007, D97).
		var rolled: bool = absf(S5Assist.roll_error(ship)) < deg_to_rad(1.0)
		if helm.level == S5HelmState.Level.ROLL or (helm.level == S5HelmState.Level.OFF and rolled):
			helm.level = S5HelmState.Level.ROLL_AND_PITCH
		else:
			helm.level = S5HelmState.Level.ROLL


func _forward_speed() -> float:
	var fwd: float = ship.velocity.dot(ship.forward())
	return clampf(fwd, -assist.max_reverse, assist.max_speed)


func _move_target() -> void:
	var w: float = TAU / target_weave_period
	var t: S5Item = items[TARGET]
	t.position = target_start + target_velocity * time + target_weave * sin(w * time)
	t.velocity = target_velocity + target_weave * w * cos(w * time)
