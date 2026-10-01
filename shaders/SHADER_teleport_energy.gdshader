shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// THE TUNNEL'S TELEPORT FLASH (SCRIPT_teleport_fx.gd). Additive light, no surface:
//   shape 0 — a column (CylinderMesh, UV.y 0 at the top): bands of energy racing
//             up it, brightest at the foot, fading to nothing at the top.
//   shape 1 — a ground ring (flat QuadMesh): a bright band at radius `progress`.
// `intensity` is the effect's envelope, driven by the script.

uniform int shape = 0;
uniform vec3 color : source_color = vec3(0.45, 0.95, 1.0);
uniform float intensity = 1.0;
uniform float progress = 0.0;
uniform float band_count = 9.0;
uniform float band_speed = 7.0;

void fragment() {
	float a = 0.0;
	if (shape == 0) {
		float h = 1.0 - UV.y;
		float bands = 0.5 + 0.5 * sin((h * band_count - TIME * band_speed) * 6.2831853);
		a = (1.0 - h) * (0.3 + 0.7 * bands) * smoothstep(0.0, 0.06, h);
	} else {
		vec2 p = UV * 2.0 - 1.0;
		float r = length(p);
		float d = (r - progress) * 9.0;
		a = exp(-d * d) * (1.0 - smoothstep(0.92, 1.0, r));
		a += (1.0 - smoothstep(0.0, 0.5, r)) * 0.4 * (1.0 - progress);
	}
	ALBEDO = color * a * intensity * 2.0;
}
