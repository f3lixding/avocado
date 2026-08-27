shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

uniform float center_opacity : hint_range(0.0, 1.0) = 0.01;
uniform float rim_opacity : hint_range(0.0, 1.0) = 0.30;
uniform float rim_power : hint_range(0.5, 8.0) = 2.5;
uniform float rainbow_strength : hint_range(0.0, 1.0) = 0.95;
uniform float rainbow_scale : hint_range(1.0, 20.0) = 10.0;
uniform float rainbow_speed : hint_range(-5.0, 5.0) = 0.15;
uniform float refraction_strength : hint_range(0.0, 0.02) = 0.002;
uniform float glow : hint_range(0.0, 2.0) = 0.12;

void fragment() {
    vec3 normal = normalize(NORMAL);
    vec3 view_direction = normalize(VIEW);

    // The shell is nearly invisible head-on and strongest around its edge.
    float facing = abs(dot(normal, view_direction));
    float rim = pow(1.0 - clamp(facing, 0.0, 1.0), rim_power);

    // Preserve the scene behind the bubble with a very small distortion.
    vec2 screen_offset = normal.xy * refraction_strength * (0.25 + rim * 0.75);
    vec3 environment_color = texture(
        screen_texture,
        SCREEN_UV + screen_offset
    ).rgb;

    // Thin-film colors appear as an angular rainbow around the highlight.
    float phase = (1.0 - facing) * rainbow_scale + TIME * rainbow_speed;
    vec3 rainbow = 0.5 + 0.5 * cos(
        phase + vec3(0.0, 2.094395, 4.188790)
    );
    float rainbow_highlight = smoothstep(0.08, 0.85, rim) * rainbow_strength;

    ALBEDO = mix(environment_color, rainbow, rainbow_highlight);
    EMISSION = rainbow * rainbow_highlight * glow;
    ALPHA = clamp(center_opacity + rim * rim_opacity, 0.0, 1.0);
}
