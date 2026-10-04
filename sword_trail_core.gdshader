shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

uniform sampler2D flame_mask : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 core_color : source_color = vec4(1.0, 0.88, 0.45, 1.0);
uniform float brightness : hint_range(0.0, 10.0) = 2.5;
uniform float opacity : hint_range(0.0, 1.0) = 0.65;

void fragment() {
    float mask = texture(flame_mask, UV).a;
    // Thin white-hot center on top of the wider orange flame silhouette.
    float core = pow(max(sin(UV.y * 3.14159265), 0.0), 10.0);
    ALBEDO = core_color.rgb;
    EMISSION = core_color.rgb * brightness;
    ALPHA = mask * core * opacity;
}
