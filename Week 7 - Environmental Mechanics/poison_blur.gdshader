shader_type canvas_item;

uniform float blur_strength : hint_range(0.0, 10.0) = 0.0;
uniform float tint_strength : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	vec4 col;

	if (blur_strength <= 0.01) {
		col = texture(screen_texture, SCREEN_UV);
	} else {
		vec2 ps = blur_strength / vec2(textureSize(screen_texture, 0));

		col = vec4(0.0);
		col += texture(screen_texture, SCREEN_UV + vec2(-2.3,  0.7) * ps) * 0.10;
		col += texture(screen_texture, SCREEN_UV + vec2( 1.8, -2.1) * ps) * 0.10;
		col += texture(screen_texture, SCREEN_UV + vec2( 0.5,  2.9) * ps) * 0.09;
		col += texture(screen_texture, SCREEN_UV + vec2(-1.6, -1.4) * ps) * 0.11;
		col += texture(screen_texture, SCREEN_UV + vec2( 2.7,  1.2) * ps) * 0.09;
		col += texture(screen_texture, SCREEN_UV + vec2(-0.4,  1.7) * ps) * 0.10;
		col += texture(screen_texture, SCREEN_UV + vec2( 1.1, -0.8) * ps) * 0.11;
		col += texture(screen_texture, SCREEN_UV + vec2(-2.8,  2.3) * ps) * 0.08;
		col += texture(screen_texture, SCREEN_UV + vec2( 0.9,  0.3) * ps) * 0.12;
		col += texture(screen_texture, SCREEN_UV + vec2(-1.2, -2.6) * ps) * 0.10;
	}

	// Very subtle tint — just a hint of green, not a flood
	col.r *= mix(1.0, 0.92, tint_strength);
	col.g *= mix(1.0, 1.05, tint_strength);
	col.b *= mix(1.0, 0.80, tint_strength);

	COLOR = col;
}
