in vec3 v_position;
in vec2 v_position_clip;

layout(location = 0) out vec3 f_albedo;

// decal texture
uniform sampler2D u_albedo_texture;

// g_buffer textures
uniform sampler2D u_normal_texture;
uniform sampler2D u_depth_texture;

uniform vec3      u_color;

uniform mat4      u_decal_vp;
uniform mat4      u_inv_view_proj;

vec3 get_world_pos() {
    float depth = texture(u_depth_texture, v_position_clip * 0.5 + 0.5).r * 2 - 1;
    vec4  ndc   = vec4(v_position_clip, depth, 1);
    vec4  world = u_inv_view_proj * ndc;
          world = world / world.w;

    return world.xyz;
}

void main() {
    vec3 world_pos = get_world_pos();
    vec4 ndc = u_decal_vp * vec4(world_pos, 1); ndc.xyz /= ndc.w;

    if (ndc.x < -1 || ndc.x > 1 || ndc.y < -1 || ndc.y > 1) {
        discard;
    }

    f_albedo = texture(u_albedo_texture, ndc.xy          * 0.5 + 0.5).rgb * u_color;
}
