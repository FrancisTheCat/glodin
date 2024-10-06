in vec2 v_tex_coords;

layout(location = 0) out vec4 f_color;

#define MAX_MATERIALS 32

UNIFORM_BUFFER(u_colors, vec4, MAX_MATERIALS);

uniform vec3      u_light_pos   = vec3(0, 2, 1);
uniform vec3      u_light_color = vec3(0.8, 0.6, 0.3);
uniform vec3      u_camera_position;
uniform sampler2D u_albedo_texture;

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

    const float ambient_strength  = 0.1;
    const float specular_strength = 0.5;

    vec3 ambient = ambient_strength * u_light_color;

    vec3 light_dir = normalize(u_light_pos - position);  

    float diff    = max(dot(normal, light_dir), 0.0);
    vec3  diffuse = diff * u_light_color;

    vec3 view_dir    = normalize(u_camera_position - position);
    vec3 reflect_dir = reflect(-light_dir, normal);  

    float spec     = pow(max(dot(view_dir, reflect_dir), 0.0), 32);
    vec3  specular = specular_strength * spec * u_light_color;  

    vec3 result = (ambient + diffuse + specular) *
        u_colors[min(material_id, MAX_MATERIALS)].rgb *
        texture(u_albedo_texture, tex_coords).rgb;
    f_color = vec4(result, 1.0);
}
