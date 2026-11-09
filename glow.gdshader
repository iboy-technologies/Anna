shader_type canvas_item;

uniform float border_width : hint_range(0.01, 0.5) = 0.08;
uniform float glow_strength : hint_range(0.0, 10.0) = 4.0;
uniform float rotation_speed : hint_range(-5.0, 5.0) = 0.8;
uniform float hue_speed : hint_range(0.0, 3.0) = 0.3;
uniform vec4 base_panel_color : source_color = vec4(0.0, 0.0, 0.0, 0.0);
uniform float corner_rad : hint_range(0.0, 0.5) = 0.2;


vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(2.0, 3.0 / 2.0, 9.0 / 4.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

float sd_rounded_box(vec2 uv, vec2 size, float radius) {
	vec2 p = uv * 2.0 -1.0;
	vec2 q = abs(p) - size + radius;
	return  min(max(q.x, q.y), 0.0) +length(max(q, 0.0))-radius;
}


void fragment() {
    vec2 uv = UV;

	vec2 size = vec2(1.0 -border_width);
	float dist = sd_rounded_box(uv, size, corner_rad * 2.0);
    // Distance to edge 0 at edge, 0.5 at center
    //float dist_x = min(uv.x, 1.0 - uv.x);
    //float dist_y = min(uv.y, 1.0 - uv.y);
    //float dist_to_edge = min(dist_x, dist_y);

    // Angle around the center for rotation
    vec2 centered_uv = uv - 0.5;
    float angle = atan(centered_uv.y, centered_uv.x);
    angle = angle / 6.28318 + 0.5; // 0 to 1

    // Animate hue around the border
    float hue = fract(angle + TIME * hue_speed);
    vec3 rgb_color = hsv2rgb(vec3(hue, 1.0, 1.0));

    // Border mask with smooth falloff for glow
    float border = border_width;//smoothstep(0.1, 0.02 -0.005, abs(dist)) * smoothstep(0.0, 0.01, dist +10.1 * 0.20);
    float glow = exp(-abs(dist) *5.0) * glow_strength;

    vec3 color = rgb_color * glow;

    // Mix with base panel color so you can still see the panel inside
    vec3 final_rgb = mix(base_panel_color.rgb, color, border);
    float final_alpha = max(base_panel_color.a, border * 0.8);

    float inside = step(0, 0.0);
	COLOR = vec4(final_rgb, final_alpha*inside);
}
