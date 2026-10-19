class_name AssistDef
extends Resource
## Flight assist tuning (FT-SIM-004, FT-SIM-036, FT-SIM-037), starting from the S5 spike.
## Units are SI (FT-SIM-033, FT-DAT-013).

## Turn rate cap in pitch and yaw at the nominal torque envelope (rad/s); it scales with
## the envelope (D117).
@export var turn_rate_pitch_yaw: float = 0.0
## Turn rate cap in roll at the nominal torque envelope (rad/s); it scales with the
## envelope (D117).
@export var turn_rate_roll: float = 0.0
## Angular rate hold time constant (s).
@export var rate_time_constant: float = 0.0
## Velocity hold time constant (s).
@export var velocity_time_constant: float = 0.0
## Attitude (face) time constant (s).
@export var attitude_time_constant: float = 0.0
## Share of the angular acceleration used to brake a turn (dimensionless, (0, 1]).
@export var attitude_braking: float = 0.0
## Lowest forward speed setpoint (m/s); negative means reverse.
@export var speed_min: float = 0.0
## Highest forward speed setpoint (m/s).
@export var speed_max: float = 0.0
## Setpoint change at full throttle input (m/s^2).
@export var speed_ramp: float = 0.0
## Hold-to-approach stand-off distance (m; FT-SIM-037 sets 500 as the data default).
@export var approach_standoff: float = 0.0
## Hold-to-approach closing speed cap (m/s).
@export var approach_speed_cap: float = 0.0
## Share of retro thrust used to brake on approach (dimensionless, (0, 1]).
@export var approach_braking: float = 0.0
## Final approach time constant (s).
@export var approach_final_time_constant: float = 0.0


func validate() -> Array[String]:
	var errors: Array[String] = []
	DefCheck.positive(errors, "turn_rate_pitch_yaw", turn_rate_pitch_yaw)
	DefCheck.positive(errors, "turn_rate_roll", turn_rate_roll)
	DefCheck.positive(errors, "rate_time_constant", rate_time_constant)
	DefCheck.positive(errors, "velocity_time_constant", velocity_time_constant)
	DefCheck.positive(errors, "attitude_time_constant", attitude_time_constant)
	DefCheck.in_range_open_low(errors, "attitude_braking", attitude_braking, 0.0, 1.0)
	if not speed_max > speed_min:
		errors.append("speed_max: must be > speed_min (%s), got %s" % [speed_min, speed_max])
	DefCheck.non_negative(errors, "speed_max", speed_max)
	DefCheck.positive(errors, "speed_ramp", speed_ramp)
	DefCheck.positive(errors, "approach_standoff", approach_standoff)
	DefCheck.positive(errors, "approach_speed_cap", approach_speed_cap)
	DefCheck.in_range_open_low(errors, "approach_braking", approach_braking, 0.0, 1.0)
	DefCheck.positive(errors, "approach_final_time_constant", approach_final_time_constant)
	return errors
