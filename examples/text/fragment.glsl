in vec2 v_tex_coords;

layout(location = 0) out vec4 f_color;

uniform sampler2D u_texture;
uniform vec4 u_color = vec4(0.8, 0.8, 0.7, 1);

void main() {
    f_color    = u_color;
    f_color.a *= texture(u_texture, vec2(v_tex_coords.x, v_tex_coords.y)).r;
}
