#version 450

layout(location = 0) in ivec2 a_position;
layout(location = 1) in  vec2 a_tex_coords;
layout(location = 2) in  vec4 a_color;

out vec2 v_tex_coords;
out vec4 v_color;

uniform vec2 u_inv_resolution;

void main() {
    v_color      = a_color;
    v_tex_coords = a_tex_coords;
    gl_Position  = vec4(vec2(1, -1) * (vec2(a_position) * u_inv_resolution * 2 - 1), 0, 1);
}
