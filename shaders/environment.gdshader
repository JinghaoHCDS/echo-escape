shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D reveal_texture : filter_nearest, repeat_disable;
uniform vec2 grid_size = vec2(36.0, 30.0);
uniform float cell_size = 1.0;
uniform float echo_time = 0.0;
uniform float reveal_duration = 2.0;
uniform vec3 player_position = vec3(0.0);
uniform bool debug_lit = false;
varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

float revealed(float arrival, float duration) {
	float age = echo_time - arrival;
	return step(0.0, age) * (1.0 - smoothstep(0.10, duration, age));
}

void fragment() {
	// Sample the traversable side of each wall. Even a pitch-black wall writes
	// opaque depth and therefore hides revealed geometry behind it.
	vec3 sample_position = world_position + world_normal * 0.08;
	vec2 cell = floor(sample_position.xz / cell_size);
	// Raised equipment above a solid footprint binds its face to the nearest
	// exposed acoustic cell; it still uses that cell's exact arrival timestamp.
	if (UV2.x >= 0.0) {
		cell = UV2;
	}
	vec2 uv = (cell + vec2(0.5)) / grid_size;
	vec2 arrivals = texture(reveal_texture, uv).rg;
	float normal_echo = revealed(arrivals.r, reveal_duration);
	float danger_echo = revealed(arrivals.g, reveal_duration);
	float echo = max(normal_echo, danger_echo);
	float danger_mix = danger_echo / max(normal_echo + danger_echo, 0.0001);
	vec3 echo_color = mix(vec3(0.40, 0.80, 0.92), vec3(0.94, 0.29, 0.09), danger_mix);
	float face_light = 0.40 + 0.32 * abs(world_normal.y) + 0.18 * abs(world_normal.x);
	// Broad wall bands and floor seams make rooms readable without triangulation.
	float wall_band = 1.0 - smoothstep(0.018, 0.055, abs(world_position.y - 0.14));
	wall_band += 0.5 * (1.0 - smoothstep(0.022, 0.060, abs(world_position.y - 2.65)));
	vec2 floor_coordinate = abs(fract(world_position.xz / 2.0) - vec2(0.5));
	float floor_seam = smoothstep(0.482, 0.495, max(floor_coordinate.x, floor_coordinate.y));
	float details = mix(wall_band * 0.42, floor_seam * 0.17, abs(world_normal.y));
	float normal_age = echo_time - arrivals.r;
	float danger_age = echo_time - arrivals.g;
	float front = max(step(0.0, normal_age) * (1.0 - smoothstep(0.0, 0.16, normal_age)),
		step(0.0, danger_age) * (1.0 - smoothstep(0.0, 0.16, danger_age)));
	float near_distance = distance(world_position.xz, player_position.xz);
	float near_floor = (1.0 - smoothstep(0.45, 1.65, near_distance))
		* (1.0 - smoothstep(0.10, 0.60, world_position.y));
	vec3 base = vec3(0.0010, 0.0020, 0.0040);
	vec3 color = base + vec3(0.008, 0.018, 0.025) * near_floor;
	color += echo_color * COLOR.rgb * (face_light + details + front * 0.14) * echo;
	if (debug_lit) {
		color = vec3(0.21, 0.29, 0.34) * COLOR.rgb * (0.65 + face_light + details);
		color += echo_color * echo * 0.17;
		// A developer-only 1m grid visualizes the actual acoustic cell resolution.
		vec2 local_grid = abs(fract(world_position.xz) - vec2(0.5));
		float grid_line = smoothstep(0.477, 0.492, max(local_grid.x, local_grid.y));
		color += vec3(0.07, 0.10, 0.12) * grid_line * abs(world_normal.y);
	}
	ALBEDO = color;
}
