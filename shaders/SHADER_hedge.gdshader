shader_type spatial;
render_mode cull_disabled, unshaded;

#include "res://shaders/SHADERINC_island_light.gdshaderinc"

// THE MAZE'S HEDGE BLOCKS (models/MODEL_hedge_chunk.glb, drawn by
// SCRIPT_hedge_maze.gd as one MultiMesh). Unshaded like everything else in the
// arena: there is no light in the scene, so the hedge lights itself off the same
// `tod_*` globals the terrain and the cliffs read, through island_light(). Fog
// is the cliff shader's, with the same numbers as the terrain material, so a
// hedge hazes out at the rate of the ground it stands on.

global uniform vec4 tod_haze_tint;

uniform sampler2D albedo_tex : source_color, filter_nearest_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);

group_uniforms light;
uniform float sun_bands = 4.0;
uniform float sun_wrap = 0.45;
uniform float rim_power = 3.0;
uniform float rim_strength = 0.2;

group_uniforms fog;
uniform bool fog_enabled = true;
uniform vec3 fog_color : source_color = vec3(0.3, 0.3, 0.3);
uniform float fog_distance_start = 850.0;
uniform float fog_distance_density = 0.0012;
uniform float fog_distance_power = 2.0;

void fragment() {
	vec3 albedo = texture(albedo_tex, UV).rgb * tint;
	// The block is authored double-sided (some of its faces wind inward), so it is
	// drawn uncull'd and a back face lights with its normal turned toward the eye.
	vec3 n = FRONT_FACING ? NORMAL : -NORMAL;
	vec3 world_n = normalize((INV_VIEW_MATRIX * vec4(n, 0.0)).xyz);
	vec3 world_v = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	albedo *= island_light(world_n, world_v, sun_bands, sun_wrap, rim_power, rim_strength);
	if (fog_enabled) {
		float fd = max(length(VERTEX) - fog_distance_start, 0.0) * fog_distance_density;
		float fog = 1.0 - exp(-pow(fd, fog_distance_power));
		albedo = mix(albedo, fog_color * tod_haze_tint.rgb, fog);
	}
	ALBEDO = albedo;
}
