#version 450

layout(location = 0) in vec3  a_position;
layout(location = 1) in vec3  a_normal;
layout(location = 2) in vec2  a_tex_coords;
layout(location = 3) in vec3  i_color;
layout(location = 4) in vec3  i_position;
layout(location = 5) in float i_scale;

uniform mat4 u_view;
uniform mat4 u_perspective;
uniform mat4 u_model;

out vec3 v_position;
out vec3 v_color;
out vec3 v_normal;
out vec2 v_tex_coords;

void main() {
    v_color      = i_color;
    v_position   = vec3(u_model * vec4(i_scale * a_position, 1)) + i_position;
    v_normal     = a_normal;
    v_tex_coords = a_tex_coords;
    gl_Position  = u_perspective * u_view * vec4(v_position, 1);
}
