shader_type spatial;
render_mode unshaded, cull_disabled;

// Mesh triangles carry geometry only. Continuous world coordinates determine
// arrival independently at every fragment, including the interiors of faces.
uniform sampler2DArray wave_distances : filter_nearest, repeat_disable;
uniform vec4 wave_origin_time[24];
uniform vec4 wave_parameters[24]; // gameplay range, signed speed, residue, visual range
uniform vec4 wave_region_parameters[24]; // source region + 1, exterior enabled, prefix, unused
uniform vec4 wave_portal_distances[24]; // each cupboard's admitted path prefix; -1 = blocked
uniform int acoustic_region_count = 0;
uniform vec4 acoustic_region_bounds[4]; // min XZ, max XZ
uniform vec4 acoustic_region_portals[4]; // portal XZ, top height, enabled
uniform vec2 grid_size = vec2(36.0, 30.0);
uniform float cell_size = 1.0;
uniform float field_resolution = 4.0;
uniform float wave_front_width = 1.5;
uniform float wave_core_transition_start = 0.8;
uniform float wave_outer_intensity = 0.18;
uniform float echo_time = 0.0;
uniform vec3 player_position = vec3(0.0);
uniform bool debug_lit = false;
varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

float planar_path(vec2 point, int layer) {
	ivec2 dimensions = textureSize(wave_distances, 0).xy;
	vec2 sample_at = point * field_resolution - vec2(0.5);
	ivec2 base = ivec2(floor(sample_at));
	ivec2 current = ivec2(floor(point * field_resolution));
	if (any(lessThan(current, ivec2(0))) || any(greaterThanEqual(current, dimensions))) {
		return -1.0;
	}
	if (texelFetch(wave_distances, ivec3(current, layer), 0).r < 0.0) {
		return -1.0;
	}
	vec2 f = fract(sample_at);
	vec4 weights = vec4((1.0-f.x)*(1.0-f.y), f.x*(1.0-f.y), (1.0-f.x)*f.y, f.x*f.y);
	vec4 d = vec4(
		texelFetch(wave_distances, ivec3(clamp(base, ivec2(0), dimensions-1), layer), 0).r,
		texelFetch(wave_distances, ivec3(clamp(base+ivec2(1,0), ivec2(0), dimensions-1), layer), 0).r,
		texelFetch(wave_distances, ivec3(clamp(base+ivec2(0,1), ivec2(0), dimensions-1), layer), 0).r,
		texelFetch(wave_distances, ivec3(clamp(base+ivec2(1,1), ivec2(0), dimensions-1), layer), 0).r
	);
	weights *= step(vec4(0.0), d);
	float total = dot(weights, vec4(1.0));
	return total > 0.00001 ? dot(max(d, vec4(0.0)), weights) / total : -1.0;
}

int region_at(vec3 point) {
	for (int region = 0; region < 4; region++) {
		if (region >= acoustic_region_count) { break; }
		vec4 bounds = acoustic_region_bounds[region];
		if (point.x >= bounds.x && point.z >= bounds.y && point.x < bounds.z && point.z < bounds.w && point.y < acoustic_region_portals[region].z) { return region; }
	}
	return -1;
}

float attenuation_at(float distance_along_path, float core, float outer) {
	float transition = core * wave_core_transition_start;
	if (distance_along_path <= transition) { return mix(1.0, 0.55, smoothstep(0.0, transition, distance_along_path)); }
	if (distance_along_path <= core) { return mix(0.55, wave_outer_intensity, smoothstep(transition, core, distance_along_path)); }
	return wave_outer_intensity * (1.0 - smoothstep(core, max(core + 0.001, outer), distance_along_path));
}

void fragment() {
	vec2 sample_position = (world_position + world_normal * 0.002).xz;
	float surface_extension = 0.0;
	// Upper surfaces of solid equipment use the exposed side as a portal,
	// then add the continuous surface offset rather than lighting a whole face.
	if (UV2.x >= 0.0) {
		vec2 exposed = clamp(sample_position, UV2 * cell_size + vec2(0.003), (UV2 + vec2(1.0)) * cell_size - vec2(0.003));
		surface_extension = distance(exposed, world_position.xz);
		sample_position = exposed;
	}
	vec3 acoustic_point = world_position + world_normal * 0.002;
	int target_region = region_at(acoustic_point);
	// The opaque top of a locker is exterior. Reach its nearest exposed edge
	// before travelling across the top instead of sampling its closed interior.
	if (target_region < 0) {
		for (int region = 0; region < 4; region++) {
			if (region >= acoustic_region_count) { break; }
			vec4 bounds = acoustic_region_bounds[region];
			// Near an exterior side, the nearest distance texel can lie inside
			// the closed region. Move the lookup out on that same face only.
			// A building-wall texel still rejects the lookup; never jump to the
			// opposite side of the cupboard or across a wall to find a sample.
			vec2 texel_center = (floor(sample_position * field_resolution) + vec2(0.5)) / field_resolution;
			bool texel_inside = texel_center.x >= bounds.x && texel_center.y >= bounds.y && texel_center.x < bounds.z && texel_center.y < bounds.w;
			if (texel_inside) {
				vec2 exposed_side = sample_position;
				float offset = 0.51 / field_resolution;
				if (sample_position.x >= bounds.z) { exposed_side.x = bounds.z + offset; }
				else if (sample_position.x <= bounds.x) { exposed_side.x = bounds.x - offset; }
				else if (sample_position.y >= bounds.w) { exposed_side.y = bounds.w + offset; }
				else if (sample_position.y <= bounds.y) { exposed_side.y = bounds.y - offset; }
				surface_extension += distance(exposed_side, sample_position);
				sample_position = exposed_side;
			}
			if (sample_position.x > bounds.x && sample_position.y > bounds.y && sample_position.x < bounds.z && sample_position.y < bounds.w) {
				vec4 edges = vec4(sample_position.x - bounds.x, sample_position.y - bounds.y, bounds.z - sample_position.x, bounds.w - sample_position.y);
				float closest = min(min(edges.x, edges.y), min(edges.z, edges.w));
				vec2 exposed = sample_position;
				if (closest == edges.x) { exposed.x = bounds.x - 0.14; }
				else if (closest == edges.y) { exposed.y = bounds.y - 0.14; }
				else if (closest == edges.z) { exposed.x = bounds.z + 0.14; }
				else { exposed.y = bounds.w + 0.14; }
				surface_extension += distance(exposed, sample_position);
				sample_position = exposed;
			}
		}
	}
	float normal_echo = 0.0;
	float danger_echo = 0.0;
	float normal_front = 0.0;
	float danger_front = 0.0;
	for (int i = 0; i < 24; i++) {
		vec4 wave = wave_parameters[i];
		if (wave.x <= 0.0 || wave.w <= 0.0) { continue; }
		vec4 origin = wave_origin_time[i];
		float elapsed = echo_time - origin.w;
		float speed = abs(wave.y);
		// Cheap sphere bound before any distance-field texture reads.
		float direct = distance(world_position, origin.xyz);
		if (elapsed < 0.0 || direct > wave.w + 0.35 || direct > elapsed * speed + 0.35) { continue; }
		vec4 region_info = wave_region_parameters[i];
		float horizontal = -1.0;
		if (target_region >= 0) {
			if (int(region_info.x) == target_region + 1) {
				horizontal = distance(world_position.xz, origin.xz);
			} else {
				float prefix = wave_portal_distances[i][target_region];
				if (prefix < 0.0) { continue; }
				horizontal = prefix + distance(world_position.xz, acoustic_region_portals[target_region].xy);
			}
		} else {
			if (region_info.y < 0.5) { continue; }
			horizontal = planar_path(sample_position, i);
			if (horizontal < 0.0) { continue; }
			horizontal += region_info.z + surface_extension;
		}
		float dy = world_position.y - origin.y;
		float distance_along_path = sqrt(horizontal * horizontal + dy * dy);
		if (distance_along_path > wave.w) { continue; }
		float age = elapsed - distance_along_path / speed;
		if (age < 0.0 || age > wave.z) { continue; }
		float behind_front = age * speed;
		// At the leading edge intensity begins at zero; the next 1.5 m smoothly
		// builds up. Nothing lights before the wall-aware front has arrived.
		float arrival_feather = smoothstep(0.0, wave_front_width, behind_front);
		float residue = (1.0 - smoothstep(0.05, wave.z, age)) * arrival_feather;
		float front = (1.0 - smoothstep(wave_front_width * 0.65, wave_front_width * 1.6, behind_front)) * arrival_feather;
		float attenuation = attenuation_at(distance_along_path, wave.x, wave.w);
		if (wave.y < 0.0) {
			danger_echo = max(danger_echo, residue * attenuation);
			danger_front = max(danger_front, front * attenuation);
		} else {
			normal_echo = max(normal_echo, residue * attenuation);
			normal_front = max(normal_front, front * attenuation);
		}
	}
	float echo = max(normal_echo, danger_echo);
	float danger_mix = danger_echo / max(normal_echo + danger_echo, 0.0001);
	vec3 echo_color = mix(vec3(0.40, 0.80, 0.92), vec3(0.94, 0.29, 0.09), danger_mix);
	float front = max(normal_front, danger_front);
	float face_light = 0.40 + 0.32 * abs(world_normal.y) + 0.18 * abs(world_normal.x);
	float wall_band = 1.0 - smoothstep(0.018, 0.055, abs(world_position.y - 0.14));
	wall_band += 0.5 * (1.0 - smoothstep(0.022, 0.060, abs(world_position.y - 2.65)));
	vec2 floor_coordinate = abs(fract(world_position.xz / 2.0) - vec2(0.5));
	float floor_seam = smoothstep(0.482, 0.495, max(floor_coordinate.x, floor_coordinate.y));
	float details = mix(wall_band * 0.42, floor_seam * 0.055, abs(world_normal.y));
	float near_distance = distance(world_position.xz, player_position.xz);
	float near_floor = (1.0 - smoothstep(0.45, 1.65, near_distance)) * (1.0 - smoothstep(0.10, 0.60, world_position.y));
	vec3 color = vec3(0.0010, 0.0020, 0.0040) + vec3(0.008, 0.018, 0.025) * near_floor;
	color += echo_color * COLOR.rgb * ((face_light * 0.35 + details * 0.7) * echo + front * 0.32);
	if (debug_lit) {
		color = vec3(0.21, 0.29, 0.34) * COLOR.rgb * (0.65 + face_light + details) + echo_color * echo * 0.17;
		vec2 local_grid = abs(fract(world_position.xz) - vec2(0.5));
		float grid_line = smoothstep(0.477, 0.492, max(local_grid.x, local_grid.y));
		color += vec3(0.07, 0.10, 0.12) * grid_line * abs(world_normal.y);
	}
	// No ALPHA: even an unrevealed wall is opaque and writes depth.
	ALBEDO = color;
}
