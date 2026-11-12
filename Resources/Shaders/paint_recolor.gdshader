shader_type spatial;
render_mode cull_disabled;

// Recolours the stock RED paint of the racer model (body, wing, rims, flame-decal base)
// to `paint_color`, and leaves everything that is not red (flames, trim, chrome, rubber) alone.
// car_model.gd puts this on the materials listed in PAINT_MATERIALS and sets paint_color = the racer's colour.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 paint_color : source_color = vec4(1.0, 0.8, 0.05, 1.0);
uniform float metallic_amount : hint_range(0.0, 1.0) = 0.4;
uniform float roughness_amount : hint_range(0.0, 1.0) = 0.3;

// Standard RGB -> HSV (hue, saturation, value all in 0..1).
vec3 rgb2hsv(vec3 c) {
	vec4 p;
	if (c.g >= c.b) {
		p = vec4(c.g, c.b, 0.0, -1.0 / 3.0);
	} else {
		p = vec4(c.b, c.g, -1.0, 2.0 / 3.0);
	}
	vec4 q;
	if (c.r >= p.x) {
		q = vec4(c.r, p.y, p.z, p.x);
	} else {
		q = vec4(p.x, p.y, p.w, c.r);
	}
	float d = q.x - min(q.w, q.y);
	float e = 0.0001;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

void fragment() {
	vec3 tex = texture(albedo_tex, UV).rgb;
	// judge "is this red?" on the display-encoded colour so the hue ranges are intuitive
	vec3 hsv = rgb2hsv(pow(tex, vec3(1.0 / 2.2)));
	float hue_dist = min(hsv.x, 1.0 - hsv.x);   // distance to pure red on the hue circle
	float is_red = (1.0 - smoothstep(0.02, 0.045, hue_dist))
			* smoothstep(0.35, 0.55, hsv.y)
			* smoothstep(0.08, 0.2, hsv.z);
	ALBEDO = mix(tex, paint_color.rgb, is_red);
	METALLIC = metallic_amount;
	ROUGHNESS = roughness_amount;
}
