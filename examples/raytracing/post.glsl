layout(location = 0) in  vec2 v_uv;

layout(location = 0) out vec4 f_color;

uniform sampler2D u_texture;
uniform float     u_inv_samples;

void main() {
    f_color = u_inv_samples * texture(u_texture, v_uv);
}
