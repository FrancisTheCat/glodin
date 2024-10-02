#version 450

     in vec4 v_color;
     in vec2 v_tex_coords;
     in vec4 v_clip_rect;
flat in int  v_use_texture;

layout(location = 0) out vec4 f_color;

uniform sampler2D u_texture;
uniform vec2      u_resolution;

void main() {
    vec2 f = gl_FragCoord.xy;
    f.y = u_resolution.y - f.y;
    if (f.x < v_clip_rect.x || f.x > v_clip_rect.z) {
        discard;
    }
    if (f.y < v_clip_rect.y || f.y > v_clip_rect.w) {
        discard;
    }
    f_color    = v_color;
    if (v_use_texture != 0) {
        f_color.a *= texture(u_texture, vec2(v_tex_coords.x, v_tex_coords.y)).r;
    }
}
