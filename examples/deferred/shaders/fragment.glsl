#version 450

in vec3 v_normal;
in vec3 v_position;

layout(location = 0) out vec3 f_position;
layout(location = 1) out vec3 f_normal;

uniform vec3 u_color;
uniform vec3 u_emission;

void main() {
    f_position = v_position;
    f_normal   = v_normal;
}
