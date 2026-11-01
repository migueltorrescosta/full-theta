class_name VfxShaders
extends RefCounted
## The two effect shaders (#12, E14, D107, D308-D311), written in code so no asset needs a
## provenance entry. Compatibility renderer only: unshaded, additive, no depth write, no
## textures, no particles. Both quantise their brightness into a few bands for the toon look.
##
## BURST is a camera-facing quad (hits, explosions, jump spool and arrival): a core flash, an
## expanding or collapsing ring and spokes, all driven by `age` (0..1). `flash` scales the core
## and the spokes (the comfort setting sets it to 0, so no flash is left, only the soft ring).
## SHIELD is a sphere shell with a rim glow and a bright patch on the side of the hit.

const _BURST_MODES: String = (
	"unshaded, blend_add, depth_draw_never, depth_test_disabled, cull_disabled,"
	+ " skip_vertex_transform"
)
const BURST: String = (
	"shader_type spatial;\nrender_mode "
	+ _BURST_MODES
	+ ";\n"
	+ """
uniform float age : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(1.0, 0.7, 0.3, 1.0);
uniform float flash = 1.0;
uniform float core = 1.0;
uniform float ring_gain = 1.0;
uniform float ring_dir = 1.0;
uniform float spokes = 8.0;
uniform float seed = 0.0;

void vertex() {
	mat4 bill = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	bill[0] *= length(MODEL_MATRIX[0].xyz);
	bill[1] *= length(MODEL_MATRIX[1].xyz);
	bill[2] *= length(MODEL_MATRIX[2].xyz);
	VERTEX = (VIEW_MATRIX * bill * vec4(VERTEX, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float fade = 1.0 - age;
	float v = flash * core * exp(-r * r * 14.0) * fade * fade * fade;
	float radius = ring_dir > 0.0 ? 0.15 + 0.8 * age : 0.95 - 0.8 * age;
	float width = 0.05 + 0.05 * fade;
	v += ring_gain * smoothstep(width, 0.0, abs(r - radius)) * (ring_dir > 0.0 ? fade : age + 0.3);
	float a = atan(p.y, p.x);
	float s = pow(max(0.0, cos(a * spokes + seed * 6.28)), 10.0);
	v += flash * s * smoothstep(0.1 + 0.9 * age, 0.0, r) * fade * 1.2;
	v *= step(r, 1.0);
	v = floor(min(v, 1.0) * 3.0) / 3.0;
	if (v < 0.3) {
		discard;
	}
	ALBEDO = tint.rgb * v;
	ALPHA = 1.0;
}
"""
)

const SHIELD: String = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never;
uniform float age : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(0.4, 0.75, 1.0, 1.0);
uniform vec3 hit_dir = vec3(0.0, 0.0, -1.0);
uniform float flash = 1.0;
varying vec3 local;

void vertex() {
	local = normalize(VERTEX);
}

void fragment() {
	float fade = 1.0 - age;
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.2);
	float d = dot(local, normalize(hit_dir));
	float patch_ = smoothstep(0.85 - 0.15 * age, 1.0, d);
	float v = 0.5 * rim * fade + flash * patch_ * fade * fade * 1.4;
	v = floor(min(v, 1.0) * 3.0) / 3.0;
	if (v < 0.3) {
		discard;
	}
	ALBEDO = tint.rgb * v;
	ALPHA = 1.0;
}
"""
