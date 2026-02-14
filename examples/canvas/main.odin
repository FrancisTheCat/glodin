package canvas

import glm "core:math/linalg/glsl"

import "vendor:glfw"

import glodin "../.."

window_x, window_y: i32

main :: proc() {
	ok := glfw.Init()
	assert(bool(ok))
	glfw.WindowHint(glfw.SAMPLES, 8)
	window := glfw.CreateWindow(900, 600, "", nil, nil)

	glfw.SetWindowSizeCallback(window, proc "c" (window: glfw.WindowHandle, x, y: i32) {
		window_x, window_y = x, y
		context = {}
		glodin.clear_color(0, 0.1)
	})

	glodin.init_glfw(window)
	defer glodin.uninit()

	Vertex_2D :: struct {
		position: glm.vec2,
	}

	vertices: []Vertex_2D = {
		{ position = 0, },
		{ position = 1, },
	}

	line := glodin.create_mesh(vertices[:])
	defer glodin.destroy(line)

	program := glodin.create_program_source(
		#load("vertex.glsl"),
		#load("fragment.glsl"),
	) or_else panic(
		"Failed to compile program",
	)
	defer glodin.destroy(program)

	for !glfw.WindowShouldClose(window) {
		if glfw.GetMouseButton(window, glfw.MOUSE_BUTTON_1) == glfw.PRESS {
			vertices[1].position = vertices[0].position
			vertices[0].position = get_cursor_position(window)
			glodin.set_mesh_data(line, vertices[:])
			glodin.draw({}, program, line, .Lines)
		} else {
			vertices[0].position = get_cursor_position(window)
		}

		glfw.SwapBuffers(window)

		glfw.PollEvents()
	}
}

get_cursor_position :: proc(window: glfw.WindowHandle) -> glm.vec2 {
	x, y := glfw.GetCursorPos(window)

	x /= f64(window_x)
	y /= f64(window_y)

	return 2 * {f32(x), f32(1 - y)} - 1
}

