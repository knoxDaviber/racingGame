shader_type spatial;
// City blocks: procedural lit windows, no textures. Works on any box size (uses world position).
render_mode cull_back;

varying vec3 wpos;
varying vec3 wnrm;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = vec2((abs(wnrm.x) > 0.5 ? wpos.z : wpos.x) / 2.6, wpos.y / 3.4);
	vec2 cell = floor(uv);
	vec2 f = fract(uv);
	float win = step(0.2, f.x) * step(f.x, 0.8) * step(0.25, f.y) * step(f.y, 0.75) * step(abs(wnrm.y), 0.5) * step(1.5, wpos.y);
	float lit = step(0.72, hash(cell + floor(wpos.xz * 0.01)));
	vec3 warm = mix(vec3(1.0, 0.75, 0.4), vec3(0.6, 0.8, 1.0), hash(cell * 1.7));
	ALBEDO = mix(vec3(0.07, 0.07, 0.09), vec3(0.12, 0.13, 0.16), win);
	ROUGHNESS = mix(0.9, 0.2, win);
	EMISSION = warm * win * lit * 0.9;
}
