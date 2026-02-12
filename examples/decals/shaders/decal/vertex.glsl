#version 450

layout(location = 0) in vec3 a_position;
layout(location = 1) in vec3 a_normal;
layout(location = 2) in vec2 a_tex_coords;

uniform mat4 u_view_proj;
uniform mat4 u_model;

out vec3 v_position;
out vec2 v_position_clip;

void main() {
    v_position      = vec3(u_model * vec4(a_position, 1));
    vec4 clip_pos   = u_view_proj * vec4(v_position, 1);
    v_position_clip = clip_pos.xy / clip_pos.w;
    gl_Position     = clip_pos;
}
