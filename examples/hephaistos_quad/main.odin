package hep_quad

import "vendor:glfw"

import glodin "../.."

W :: 1920
H :: 1080

main :: proc() {
	ok := glfw.Init()
	assert(bool(ok))
	window := glfw.CreateWindow(W, H, "", nil, nil)

	glodin.init_glfw(window)
	defer glodin.uninit()

	Vertex_2D :: struct {
		position:   [2]f32,
		tex_coords: [2]f32,
	}

	vertices: []Vertex_2D = {
		{ position = { -1, -1, }, tex_coords = { 0, 0, }, },
		{ position = { +1, -1, }, tex_coords = { 1, 0, }, },
		{ position = { -1, +1, }, tex_coords = { 0, 1, }, },
		{ position = { +1, +1, }, tex_coords = { 1, 1, }, },
	}

	indices: []u32 = { 0, 1, 2, 2, 1, 3, }

	quad := glodin.create_mesh(vertices, indices)
	defer glodin.destroy(quad)

	program := glodin.create_program_hephaistos(#load("shader.hep")) or_else panic(
		"Failed to compile program",
	)
	defer glodin.destroy(program)

	transform := matrix[3, 3]f32{
		0.5, 0,   0,
		0,   0.5, 0,
		0,   0,   1,
	}
	glodin.set_uniforms(program, {
		{ "u_color",     [4]f32{ 1, 0.5, 0.25, 1, }, },
		{ "u_transform", transform,                  },
	})

	for !glfw.WindowShouldClose(window) {
		glodin.draw({}, program, quad)
		glfw.SwapBuffers(window)
		glfw.PollEvents()
	}
}
