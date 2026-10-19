class_name ClientSettings
extends RefCounted
## Per-client settings, persisted in one ConfigFile under user:// (path injectable for
## tests): the player's name, bindings and hold-to-toggle choices (FT-STN-007,
## FT-STN-014), UI scale (FT-STN-013), first-run tooltips already seen (FT-STN-012),
## invert pitch (S5) and the comfort options (FT-STN-017: the station cameras read
## them; the cosmetic reference plane is never spoken or used by rules, D124).

const PATH: String = "user://client_settings.cfg"
const UI_SCALE_MIN: float = 0.75
const UI_SCALE_MAX: float = 1.5
const UI_SCALE_STEP: float = 0.05
## Comfort roll locks: the ship's deck plane, the selected target, or the player's
## cosmetic reference plane.
const ROLL_LOCKS: Array[String] = ["deck", "target", "reference"]

var path: String = PATH
var player_name: String = ""
## Last address typed in Join.
var last_address: String = ""
var ui_scale: float = 1.0
var invert_pitch: bool = false
## Station id -> true once its first-run tooltip was dismissed.
var tooltips_seen: Dictionary = {}
## Comfort (FT-STN-017): on/off, roll lock, reduced field of view, and the cosmetic
## reference plane as a world orientation ("Set reference plane to my current deck").
var comfort: bool = false
var roll_lock: String = "deck"
var reduced_fov: bool = false
var reference_plane: Quaternion = Quaternion.IDENTITY
var bindings: Bindings = Bindings.new()


func _init(file_path: String = PATH) -> void:
	path = file_path


## Reads the file; a missing file keeps the defaults (OK).
func load_file() -> Error:
	var cfg: ConfigFile = ConfigFile.new()
	var err: Error = cfg.load(path)
	if err == ERR_FILE_NOT_FOUND:
		return OK
	if err != OK:
		return err
	player_name = str(cfg.get_value("player", "name", ""))
	last_address = str(cfg.get_value("player", "last_address", ""))
	set_ui_scale(float(cfg.get_value("ui", "scale", 1.0)))
	invert_pitch = bool(cfg.get_value("input", "invert_pitch", false))
	var b: Variant = cfg.get_value("input", "bindings", {})
	bindings.from_dict(b if b is Dictionary else {})
	var seen: Variant = cfg.get_value("ui", "tooltips_seen", [])
	tooltips_seen.clear()
	for s: Variant in seen if seen is Array else []:
		tooltips_seen[str(s)] = true
	comfort = bool(cfg.get_value("comfort", "on", false))
	var lock: String = str(cfg.get_value("comfort", "roll_lock", "deck"))
	roll_lock = lock if lock in ROLL_LOCKS else "deck"
	reduced_fov = bool(cfg.get_value("comfort", "reduced_fov", false))
	var q: Variant = cfg.get_value("comfort", "reference_plane", Quaternion.IDENTITY)
	reference_plane = q if q is Quaternion else Quaternion.IDENTITY
	return OK


func save() -> Error:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("player", "name", player_name)
	cfg.set_value("player", "last_address", last_address)
	cfg.set_value("ui", "scale", ui_scale)
	cfg.set_value("ui", "tooltips_seen", tooltips_seen.keys())
	cfg.set_value("input", "invert_pitch", invert_pitch)
	cfg.set_value("input", "bindings", bindings.to_dict())
	cfg.set_value("comfort", "on", comfort)
	cfg.set_value("comfort", "roll_lock", roll_lock)
	cfg.set_value("comfort", "reduced_fov", reduced_fov)
	cfg.set_value("comfort", "reference_plane", reference_plane)
	return cfg.save(path)


## 75-150 % in 5 % steps (FT-STN-013).
func set_ui_scale(value: float) -> void:
	ui_scale = clampf(snappedf(value, UI_SCALE_STEP), UI_SCALE_MIN, UI_SCALE_MAX)


func tooltip_seen(station: String) -> bool:
	return tooltips_seen.has(station)


func mark_tooltip_seen(station: String) -> void:
	tooltips_seen[station] = true


## Settings: "Show first-run tips again" (FT-STN-012).
func reset_tooltips() -> void:
	tooltips_seen.clear()
