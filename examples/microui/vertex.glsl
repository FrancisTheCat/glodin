#version 450

layout(location = 0) in vec2 a_position;
layout(location = 1) in vec4 a_color;

out vec4 v_color;

void main() {
    v_color      = a_color;
    gl_Position  = vec4(vec2(1, -1) * (a_position * 2 - 1), 0, 1);
}
