// S8 cel shader: three light bands and a rim highlight (Compatibility renderer).
shader_type spatial;
render_mode specular_disabled;

uniform vec4 albedo : source_color = vec4(1.0);
uniform vec4 glow : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float rim_strength = 0.35;

void fragment() {
	ALBEDO = albedo.rgb;
	float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	EMISSION = glow.rgb + albedo.rgb * rim_strength * step(0.68, rim);
}

void light() {
	float ndl = dot(NORMAL, LIGHT) * ATTENUATION;
	float band = ndl > 0.5 ? 1.0 : (ndl > 0.05 ? 0.6 : 0.25);
	// LIGHT_COLOR carries a factor of PI.
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * band;
}
