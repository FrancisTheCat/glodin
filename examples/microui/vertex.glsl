layout(location = 0) in vec2 a_position;

layout(location = 1) in ivec2 i_position;
layout(location = 2) in ivec2 i_scale;
layout(location = 3) in vec4  i_tex_rect;
layout(location = 4) in ivec4 i_clip_rect;
layout(location = 5) in vec4  i_color;

     out vec2  v_tex_coords;
     out vec4  v_color;
flat out ivec4 v_clip_rect;
flat out int   v_use_texture;

uniform vec2 u_inv_resolution;

void main() {
    v_clip_rect    = i_clip_rect;
    v_tex_coords   = i_tex_rect.xy + i_tex_rect.zw * a_position;
    v_use_texture  = (i_tex_rect.zw == vec2(0)) ? 0 : 1;
    v_color        = i_color;
    gl_Position    = vec4(
        vec2(1, -1) * (u_inv_resolution * (vec2(i_scale) * a_position + vec2(i_position)) * 2 - 1),
        0,
        1
    );
}
