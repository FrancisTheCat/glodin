#version 450

in vec2 v_tex_coords;

layout(location = 0) out vec4 f_color;

uniform usampler2D u_game_state;

void main() {
    f_color.rgb = (texture(u_game_state, v_tex_coords).r != 0) ? vec3(0.8, 0.8, 0.7) : vec3(0.1);
    f_color.a = 1;
}
