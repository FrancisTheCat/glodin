#version 450

in vec3 v_normal;
in vec3 v_position;
in vec2 v_tex_coords;

layout(location = 0) out vec3 f_position;
layout(location = 1) out vec3 f_normal;
layout(location = 2) out vec3 f_albedo;

uniform sampler2D u_albedo_texture;
uniform vec3      u_color;

void main() {
    f_position    = v_position;
    f_normal      = v_normal;
    f_albedo      = texture(u_albedo_texture, v_tex_coords).rgb * u_color;
}
