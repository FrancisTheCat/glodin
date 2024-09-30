#version 450

in vec3 v_normal;
in vec3 v_position;

layout(location = 0) out vec4 f_color;

uniform vec3 u_color;
uniform vec3 u_emission;

void main() {
    f_color.rgb = u_color * (0.5 + 0.5 * dot(normalize(v_normal), normalize(vec3(1, 3, 2)))) + u_emission;
    f_color.a = 1;
}
