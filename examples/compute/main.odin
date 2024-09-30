package compute

import "vendor:glfw"

import glodin "../.."

W :: 1024 * 4
H :: 1024 * 4

main :: proc() {
	assert(glfw.Init() != false)
	glfw.WindowHint(glfw.VISIBLE, false)
	window := glfw.CreateWindow(1, 1, "", nil, nil)
	glfw.MakeContextCurrent(window)

	glodin.init(glfw.gl_set_proc_address)
	defer glodin.uninit()

	compute := glodin.create_compute_file("compute.glsl") or_else panic("Failed to compile compute shader")
	defer glodin.destroy(compute)

	compute_texture := glodin.create_texture_empty(W, H, .RGBA8)
	defer glodin.destroy(compute_texture)

	glodin.dispatch_compute(compute, {W, H, 1}, {"img_output", compute_texture})

	assert(glodin.write_texture_to_png(compute_texture, "compute_output.png", 3))
}

