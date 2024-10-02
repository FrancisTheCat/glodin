#version 450

in vec4 v_color;

layout(location = 0) out vec4 f_color;

uniform sampler2D u_texture;

void main() {
    f_color    = v_color;
    // f_color.a *= texture(u_texture, vec2(v_tex_coords.x, v_tex_coords.y)).r;
}
