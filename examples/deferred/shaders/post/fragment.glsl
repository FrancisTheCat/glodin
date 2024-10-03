#version 450

in vec2 v_tex_coords;

layout(location = 0) out vec4 f_color;

uniform  sampler2D u_texture_position;
uniform  sampler2D u_texture_normal;
uniform  sampler2D u_texture_tex_coords;
uniform isampler2D u_texture_material;
uniform  sampler2D u_texture_depth;

void main() {
    vec3  normal      = texture(u_texture_normal,     v_tex_coords).xyz;
    vec3  position    = texture(u_texture_position,   v_tex_coords).xyz;
    vec2  tex_coords  = texture(u_texture_tex_coords, v_tex_coords).xy;
    int   material_id = texture(u_texture_material,   v_tex_coords).x;
    float depth       = texture(u_texture_depth,      v_tex_coords).r;

    /* some kind of shading code would go here */

    f_color.rgb  = (position * 0.5 + 0.5) * (dot(normal, normalize(vec3(2, 3, 1))) * 0.5 + 0.5) * depth;
    f_color.rg  *= tex_coords;
    f_color.b   *= float(material_id);
    f_color.a    = 1;
}
