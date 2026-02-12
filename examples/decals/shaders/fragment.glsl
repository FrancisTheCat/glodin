#version 450

in vec3 v_normal;
in vec3 v_position;
in vec2 v_tex_coords;

layout(location = 0) out vec3 f_color;
layout(location = 1) out vec3 f_normal;

uniform sampler2D u_albedo_texture;
uniform vec3      u_color;

void main() {
    f_color  = texture(u_albedo_texture, v_tex_coords).rgb * u_color;
    f_color  = f_color * 0.001 + u_color;
    f_normal = v_normal;
}
