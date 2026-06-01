shader_type canvas_item;

uniform float pulse_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec4 vignette_color : source_color = vec4(0.6, 0.0, 0.0, 1.0);

// How far the vignette eats inward from the edges (0=none, 1=full screen)
const float VIGNETTE_SIZE = 1.1;
// Corner roundness (0=sharp square, 1=fully circular)
const float CORNER_RADIUS = 0.2;
// Softness of the falloff edge
const float FEATHER = 0.15;

void fragment() {
    vec2 centered = abs(UV - vec2(0.5));

    // SDF for a rounded rectangle
    vec2 q = centered - vec2(VIGNETTE_SIZE * 0.5 - CORNER_RADIUS);
    float dist = length(max(q, 0.0)) - CORNER_RADIUS;

    // dist < 0 = inside the rounded rect (center, no vignette)
    // dist > 0 = outside (edges/corners, full vignette)
    float mask = smoothstep(-FEATHER, 0.0, dist);

    COLOR = vec4(vignette_color.rgb, mask * pulse_strength);
}