in vec2 v_tex_coords;

layout(location = 0) out vec4 f_color;

uniform sampler2D u_texture_color;
uniform sampler2D u_texture_bloom;

float luminance(vec3 v) {
    return dot(v, vec3(0.2126f, 0.7152f, 0.0722f));
}

vec3 reinhard_jodie(vec3 v) {
    float l = luminance(v);
    vec3 tv = v / (1.0f + v);
    return mix(v / (1.0f + l), tv, tv);
}

vec3 reinhard(vec3 x) {
    return x * (1.0 + (x / vec3(8 * 8))) / (x + 1);
}

vec3 aces(vec3 x) {
    const float a = 2.51;
    const float b = 0.03;
    const float c = 0.43;
    const float d = 1.59;
    const float e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

vec3 tonemap(vec3 x) {
    return reinhard_jodie(x);
}

void main() {
    f_color.rgb = tonemap(mix(
        texture(u_texture_color, v_tex_coords).rgb,
        texture(u_texture_bloom, v_tex_coords).rgb,
        0.15
    ));
    f_color.a = 1;
}
