#version 450

in vec2 v_tex_coords;
in vec3 v_normal;
in vec3 v_color;

layout(location = 0) out vec4 f_color;

uniform sampler2D texture;

void main() {
    f_color.rgb = v_color * (0.5 + 0.5 * dot(normalize(v_normal), normalize(vec3(1, 3, 2))));
    f_color.a = 1;
}
