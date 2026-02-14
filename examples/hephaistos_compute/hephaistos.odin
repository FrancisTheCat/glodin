package hephaistos_example

import "core:math/rand"

import "vendor:glfw"

import glodin "../.."

W :: 2560
H :: 1440

main :: proc() {
	assert(glfw.Init() != false)
	glfw.WindowHint(glfw.VISIBLE, false)
	window := glfw.CreateWindow(1, 1, "", nil, nil)
	glfw.MakeContextCurrent(window)

	glodin.init(glfw.gl_set_proc_address)
	defer glodin.uninit()

	compute := glodin.create_compute_hephaistos(#load("shader.hep")) or_else panic("Failed to compile compute shader")
	defer glodin.destroy(compute)

	compute_texture := glodin.create_texture_empty(W, H, .RGBA8)
	defer glodin.destroy(compute_texture)

	noise_texture_data := make([]u8, W * H)
	for i in 0 ..< len(noise_texture_data) / 8 {
		(cast(^u64)&noise_texture_data[i * 8])^ = rand.uint64()
	}
	noise_texture := glodin.create_texture_with_data(W, H, noise_texture_data)
	defer glodin.destroy(noise_texture)

	glodin.dispatch_compute(compute, { W, H, 1, }, {
		{ "img_output", compute_texture, },
		{ "img_noise",  noise_texture,   },
	})

	assert(glodin.write_texture_to_png(compute_texture, "compute_output.png", 3))
}

