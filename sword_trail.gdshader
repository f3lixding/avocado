shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

uniform vec4 outer_color : source_color = vec4(1.0, 0.08, 0.005, 1.0);
uniform vec4 middle_color : source_color = vec4(1.0, 0.38, 0.015, 1.0);
uniform vec4 core_color : source_color = vec4(1.0, 0.92, 0.48, 1.0);
uniform float emission_strength : hint_range(0.0, 12.0) = 4.0;
uniform float opacity : hint_range(0.0, 1.0) = 0.85;
uniform float scroll_speed : hint_range(-5.0, 5.0) = 1.4;
uniform vec2 noise_scale = vec2(5.0, 3.0);
uniform float tail_fade : hint_range(0.01, 1.0) = 0.32;
uniform float edge_power : hint_range(0.1, 4.0) = 0.55;
uniform float dissolve : hint_range(0.0, 1.0) = 0.36;
uniform float flicker_strength : hint_range(0.0, 1.0) = 0.45;

float random_value(vec2 point) {
    return fract(sin(dot(point, vec2(127.1, 311.7))) * 43758.5453123);
}

float value_noise(vec2 point) {
    vec2 cell = floor(point);
    vec2 fraction = fract(point);
    fraction = fraction * fraction * (3.0 - 2.0 * fraction);

    float a = random_value(cell);
    float b = random_value(cell + vec2(1.0, 0.0));
    float c = random_value(cell + vec2(0.0, 1.0));
    float d = random_value(cell + vec2(1.0, 1.0));

    return mix(mix(a, b, fraction.x), mix(c, d, fraction.x), fraction.y);
}

float fbm(vec2 point) {
    float result = 0.0;
    float amplitude = 0.5;

    for (int octave = 0; octave < 4; octave++) {
        result += value_noise(point) * amplitude;
        point = point * 2.03 + vec2(17.1, 9.2);
        amplitude *= 0.5;
    }

    return result;
}

void fragment() {
    // UV.x runs from the old tail (0) to the sword (1). UV.y crosses the blade.
    float tail_mask = smoothstep(0.0, tail_fade, UV.x);
    float edge_mask = pow(max(sin(UV.y * 3.14159265), 0.0), edge_power);
    float ribbon_mask = tail_mask * edge_mask;

    vec2 flowing_uv = UV * noise_scale;
    flowing_uv.x -= TIME * scroll_speed;
    flowing_uv.y += sin(TIME * 2.1 + UV.x * 8.0) * 0.25;

    float large_flame = fbm(flowing_uv);
    float fine_flame = fbm(flowing_uv * 1.83 + vec2(TIME * 0.37, -TIME * 0.21));
    float noise = mix(large_flame, fine_flame, 0.35);

    float noisy_shape = noise + ribbon_mask * (1.0 - flicker_strength);
    float flame_mask = smoothstep(dissolve - 0.12, dissolve + 0.12, noisy_shape);
    float alpha = ribbon_mask * flame_mask * opacity;

    float heat = clamp(ribbon_mask * (0.55 + noise * 0.85), 0.0, 1.0);
    vec3 color = mix(outer_color.rgb, middle_color.rgb, smoothstep(0.05, 0.58, heat));
    color = mix(color, core_color.rgb, smoothstep(0.58, 1.0, heat));

    ALBEDO = color;
    EMISSION = color * emission_strength * (0.45 + heat);
    ALPHA = alpha;
}
