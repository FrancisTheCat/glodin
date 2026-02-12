#version 450

in vec2 v_tex_coords;

layout(location = 0) out vec4 f_color;

uniform vec3 u_light_dir   = normalize(vec3(1, 2, 1));
uniform vec3 u_light_color = vec3(0.8, 0.6, 0.3);

uniform sampler2D u_texture_normal;
uniform sampler2D u_texture_albedo;
uniform sampler2D u_texture_depth;

void main() {
    vec3  normal = normalize(texture(u_texture_normal, v_tex_coords).xyz);
    vec3  albedo =           texture(u_texture_albedo, v_tex_coords).rgb;
    float depth  =           texture(u_texture_depth,  v_tex_coords).r;

    vec3 result = (0.5 + 0.5 * dot(u_light_dir, normal)) * albedo * u_light_color;
    f_color = vec4(result, 1.0);
}

