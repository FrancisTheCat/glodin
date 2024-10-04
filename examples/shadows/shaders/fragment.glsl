layout (location = 0) in vec3 v_position;
layout (location = 1) in vec3 v_normal;

layout (location = 0) out vec4 f_color;

uniform vec3      u_light_direction;
uniform mat4      u_shadow_matrix;
uniform sampler2D u_depth_texture;

void main() {
    vec4  _shadow_position = (u_shadow_matrix * vec4(v_position, 1));
    vec3  shadow_position  = (_shadow_position.xyz / _shadow_position.w) * 0.5 + 0.5;
    float sample_depth     = texture(u_depth_texture, shadow_position.xy).r;
    float depth            = shadow_position.z;

    if (depth < sample_depth + 0.01) {
        f_color.rgb = vec3(clamp(dot(v_normal, u_light_direction), 0, 1));
    } else {
        f_color.rgb = vec3(0);
    }

    f_color.a = 1;
}
