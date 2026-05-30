shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

uniform vec4 emission_color : source_color = vec4(1.0, 0.9, 0.2, 1.0);
uniform float emission_energy : hint_range(0.0, 8.0) = 1.0;
uniform float base_alpha : hint_range(0.0, 1.0) = 0.3;  // Opacity at the bottom

void fragment() {
	// UV.y on a CylinderMesh runs 0 (top) to 1 (bottom)
	float t = 1.0 - UV.y;  // Flip so 0 = bottom, 1 = top
	t = clamp(t, 0.0, 1.0);
	float alpha = base_alpha * (1.0 - t);
	ALBEDO = emission_color.rgb * emission_energy;
	ALPHA = alpha;
}
