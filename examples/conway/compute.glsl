layout (local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

layout(r8ui) uniform writeonly uimage2D img_output;
layout(r8ui) uniform readonly  uimage2D img_input;

void main() {
    ivec2 coord = ivec2(gl_GlobalInvocationID.xy);

    ivec2 image_size = imageSize(img_input);

    int n_neighbours = 0;
    for (int y = -1; y < 2; y += 1) {
        for (int x = -1; x < 2; x += 1) {
            ivec2 nc = coord + ivec2(x, y);
            if (x == 0 && y == 0 || nc.x < 0 || nc.y < 0 || nc.x > image_size.x || nc.y > image_size.y) {
                continue;
            }
            if (imageLoad(img_input, nc).r != 0) {
                n_neighbours += 1;
            }
        }
    }

    uint alive = imageLoad(img_input, coord).r;
    if (alive != 0) {
        if (n_neighbours < 2) {
            alive = 0;
        }
        if (n_neighbours > 3) {
            alive = 0;
        }
    } else {
        if (n_neighbours == 3) {
            alive = 255;
        }
    }
    imageStore(img_output, coord, uvec4(alive));
}
