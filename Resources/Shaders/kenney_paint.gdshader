shader_type spatial;
render_mode cull_disabled;

// Repaints the BODY PAINT of a Kenney Car Kit car. All Kenney cars share one palette texture (colormap.png, 8 x 4 blocks);
// the body paint of the cars we use sits in row 1, columns 3 (green), 6 (red) and 7 (blue). Everything else (windows, trim,
// lights, tyres, rims) is left alone. The block's own light-to-dark gradient is kept as shading.

uniform sampler2D albedo_tex : source_color, filter_linear, repeat_disable;
uniform vec4 paint_color : source_color = vec4(1.0, 0.8, 0.05, 1.0);
uniform float metallic_amount : hint_range(0.0, 1.0) = 0.25;
uniform float roughness_amount : hint_range(0.0, 1.0) = 0.45;

void fragment() {
	vec3 tex = texture(albedo_tex, UV).rgb;
	bool row = UV.y >= 0.25 && UV.y < 0.5;
	bool col = (UV.x >= 0.375 && UV.x < 0.5) || UV.x >= 0.75;
	float shade = max(tex.r, max(tex.g, tex.b));   // the block's gradient, 0.8 .. 1.0 in display colour
	vec3 painted = paint_color.rgb * clamp(shade / 0.9, 0.55, 1.15);
	ALBEDO = (row && col) ? painted : tex;
	METALLIC = (row && col) ? metallic_amount : 0.0;
	ROUGHNESS = (row && col) ? roughness_amount : 0.8;
}
