// S8 inverted-hull outline: the back faces of a mesh pushed out along smoothed normals.
shader_type spatial;
render_mode unshaded, cull_front;

uniform vec4 color : source_color = vec4(0.08, 0.06, 0.14, 1.0);
uniform float width = 0.05;

void vertex() {
	VERTEX += NORMAL * width;
}

void fragment() {
	ALBEDO = color.rgb;
}
