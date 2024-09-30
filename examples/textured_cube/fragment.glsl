#version 450

layout (location = 0) in vec3 v_position;
layout (location = 1) in vec3 v_normal;
layout (location = 2) in vec2 v_tex_coords;

layout (location = 0) out vec4 f_color;

uniform sampler2D u_texture;

void main() {
    f_color.rgb = texture(u_texture, v_tex_coords).rgb *
        (0.5 + 0.5 * dot(v_normal, normalize(vec3(1, 2, -1))));
    f_color.a = 1;
}
