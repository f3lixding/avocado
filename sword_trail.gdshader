shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// A hand-drawn silhouette: U=0 is the tail; U=1 is the current sword position.
uniform sampler2D flame_mask : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 ember_color : source_color = vec4(0.75, 0.06, 0.005, 1.0);
uniform vec4 flame_color : source_color = vec4(1.0, 0.38, 0.015, 1.0);
uniform float opacity : hint_range(0.0, 1.0) = 0.8;
uniform float glow : hint_range(0.0, 8.0) = 1.8;

void fragment() {
    vec4 shape = texture(flame_mask, UV);
    // Flicker the color slightly, not the outline: the authored silhouette
    // stays continuous instead of breaking up into rectangular sections.
    float flicker = 0.87 + 0.13 * sin(UV.x * 42.0 - TIME * 18.0);
    float warmth = smoothstep(0.1, 0.85, UV.y);
    vec3 color = mix(ember_color.rgb, flame_color.rgb, warmth) * flicker;

    ALBEDO = color;
    EMISSION = color * glow;
    ALPHA = shape.a * opacity;
}
