class_name VfxEffect
extends MeshInstance3D
## One short effect on the 3D views (#12, E14): a hit spark, a shield hit, an explosion, the
## jump drive spooling or arriving. A shader-driven quad or sphere (VfxShaders), no particles.
## It follows `age` and frees itself at `duration`. With `frozen` it holds its age, for the
## L5 shots. Comfort (FT-STN-017) takes the flash out: `flash` is 0, only the soft ring or
## the shell's rim stays, dimmer.

enum Kind { HIT, SHIELD, EXPLOSION, JUMP_SPOOL, JUMP_ARRIVE }

## Per kind: duration (s), size (model units for a quad, radius for the shield), colour and,
## for a quad, the spokes, the core gain, the ring gain and the ring direction.
const SPEC: Dictionary = {
	Kind.HIT:
	{
		"s": 0.45,
		"size": 4.0,
		"tint": Color(1.0, 0.75, 0.35),
		"spokes": 7.0,
		"core": 1.0,
		"ring": 0.5,
		"dir": 1.0,
	},
	Kind.SHIELD: {"s": 0.6, "size": 3.3, "tint": Color(0.4, 0.75, 1.0)},
	Kind.EXPLOSION:
	{
		"s": 1.4,
		"size": 11.0,
		"tint": Color(1.0, 0.55, 0.2),
		"spokes": 11.0,
		"core": 1.3,
		"ring": 1.0,
		"dir": 1.0,
	},
	Kind.JUMP_SPOOL:
	{
		"s": 1.2,
		"size": 8.0,
		"tint": Color(0.75, 0.55, 1.0),
		"spokes": 0.0,
		"core": 0.0,
		"ring": 1.0,
		"dir": -1.0,
	},
	Kind.JUMP_ARRIVE:
	{
		"s": 0.9,
		"size": 10.0,
		"tint": Color(0.85, 0.95, 1.0),
		"spokes": 16.0,
		"core": 1.6,
		"ring": 1.0,
		"dir": 1.0,
	},
}
## Share of the ring or rim kept with comfort on.
const COMFORT_SOFT: float = 0.6

static var _burst_shader: Shader
static var _shield_shader: Shader

var kind: Kind = Kind.HIT
var duration: float = 0.5
var age: float = 0.0
## The core and spoke gain (0 with comfort on).
var flash: float = 1.0
var frozen: bool = false
var _material: ShaderMaterial


## A new effect of `p_kind`. `direction` (model frame) places a shield's bright patch;
## `seed_value` varies the spokes.
static func make(
	p_kind: Kind, comfort: bool, direction: Vector3 = Vector3.FORWARD, seed_value: float = 0.0
) -> VfxEffect:
	var e: VfxEffect = VfxEffect.new()
	var spec: Dictionary = SPEC[p_kind]
	e.kind = p_kind
	e.duration = float(spec["s"])
	e.flash = 0.0 if comfort else 1.0
	e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var soft: float = COMFORT_SOFT if comfort else 1.0
	var mat: ShaderMaterial = ShaderMaterial.new()
	if p_kind == Kind.SHIELD:
		var sphere: SphereMesh = SphereMesh.new()
		sphere.radius = float(spec["size"])
		sphere.height = 2.0 * float(spec["size"])
		sphere.radial_segments = 24
		sphere.rings = 12
		e.mesh = sphere
		mat.shader = _shader(true)
		mat.set_shader_parameter("hit_dir", direction)
		mat.set_shader_parameter("tint", spec["tint"])
	else:
		var quad: QuadMesh = QuadMesh.new()
		quad.size = Vector2.ONE * float(spec["size"])
		e.mesh = quad
		mat.shader = _shader(false)
		mat.set_shader_parameter("tint", spec["tint"])
		mat.set_shader_parameter("spokes", spec["spokes"])
		mat.set_shader_parameter("core", spec["core"])
		mat.set_shader_parameter("ring_gain", float(spec["ring"]) * soft)
		mat.set_shader_parameter("ring_dir", spec["dir"])
		mat.set_shader_parameter("seed", seed_value)
	mat.set_shader_parameter("flash", e.flash)
	e._material = mat
	e.material_override = mat
	e.set_age(0.0)
	return e


static func _shader(shield: bool) -> Shader:
	if _burst_shader == null:
		_burst_shader = Shader.new()
		_burst_shader.code = VfxShaders.BURST
		_shield_shader = Shader.new()
		_shield_shader.code = VfxShaders.SHIELD
	return _shield_shader if shield else _burst_shader


func _process(delta: float) -> void:
	if not frozen:
		advance(delta)


## Moves the effect `dt` seconds on; frees it past its duration.
func advance(dt: float) -> void:
	set_age(age + dt)
	if age >= duration:
		queue_free()


## Sets the age (s) and the shader to match.
func set_age(t: float) -> void:
	age = t
	_material.set_shader_parameter("age", clampf(t / duration, 0.0, 1.0))


## Whether the effect is over.
func finished() -> bool:
	return age >= duration
