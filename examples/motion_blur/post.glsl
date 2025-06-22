layout(location = 0) in  vec2 v_uv;

layout(location = 0) out vec4 f_color;

uniform sampler2D u_texture;
uniform float     u_inv_samples;

vec3 aces(vec3 x) {
    const float a = 2.51;
    const float b = 0.03;
    const float c = 0.43;
    const float d = 1.59;
    const float e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

void main() {
    f_color.rgb = aces(u_inv_samples * texture(u_texture, v_uv).rgb);
}
