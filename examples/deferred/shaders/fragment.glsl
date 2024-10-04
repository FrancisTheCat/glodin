in vec3 v_normal;
in vec3 v_position;
in vec2 v_tex_coords;

layout(location = 0) out vec3 f_position;
layout(location = 1) out vec3 f_normal;
layout(location = 2) out vec2 f_tex_coords;
layout(location = 3) out int  f_material_id;

uniform int u_material_id;

void main() {
    f_position    = v_position;
    f_normal      = v_normal;
    f_tex_coords  = v_tex_coords;
    f_material_id = u_material_id;
}
