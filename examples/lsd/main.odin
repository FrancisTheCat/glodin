package example

import "base:runtime"

import "core:log"

@(require) import "core:fmt"
import glm "core:math/linalg/glsl"
import "core:strings"
import "core:time"

import "vendor:glfw"

import glodin "../.."

program: glodin.Program

quad: glodin.Mesh

main :: proc() {
	context.logger = log.create_console_logger(ODIN_DEBUG ? .Debug : .Error)
	callback_context = context

	window_init()
	defer window_uninit()

	Vertex_2D :: struct {
		position:   glm.vec2,
		tex_coords: glm.vec2,
	}

	vertices: []Vertex_2D = {
		{position = {-1, -1}, tex_coords = {0, 0}},
		{position = {+1, -1}, tex_coords = {1, 0}},
		{position = {-1, +1}, tex_coords = {0, 1}},
		{position = {+1, +1}, tex_coords = {1, 1}},
	}

	indices: []u32 = {0, 1, 2, 2, 1, 3}

	quad = glodin.create_mesh(vertices, indices)
	defer glodin.destroy(quad)

	program =
		glodin.create_program_file("vertex.glsl", "fragment.glsl") or_else panic(
			"Failed to compile program",
		)
	defer glodin.destroy(program)

	glodin.disable(.Cull_Face, .Depth_Test)

	start_time := time.now()
	total_time: f64
	for !window.should_close {
		total_time = f64(time.duration_seconds(time.since(start_time)))

		glodin.clear_color(0, {0.1, 0.1, 0.1, 1})

		glodin.set_uniforms(program, {
			{"u_time", f32(total_time) * 0.333},
			{"u_aspect", f32(window.aspect_ratio)},
			{"u_inv_resolution", 1.0 / glm.vec2{f32(window.width), f32(window.height)}},
		})
		glodin.draw(0, program, quad)

		window_poll()
	}
}

window: Window

Window :: struct {
	handle:        glfw.WindowHandle,
	width, height: int,
	aspect_ratio:  f32,
	should_close:  bool,
}

set_window_title :: proc(title: string) {
	glfw.SetWindowTitle(window.handle, strings.clone_to_cstring(title, context.temp_allocator))
}

window_poll :: proc() {
	glfw.SwapBuffers(window.handle)

	glfw.PollEvents()
	window.should_close = bool(glfw.WindowShouldClose(window.handle))
}

window_init :: proc() {
	if !glfw.Init() {
		log.panic("GLFW has failed to load.")
	}

	window.handle = glfw.CreateWindow(900, 600, "GLODIN", nil, nil)

	if window.handle == nil {
		log.panic("GLFW has failed to load the window.")
	}

	w, h := glfw.GetWindowSize(window.handle)
	window.width = int(w)
	window.height = int(h)
	window.aspect_ratio = f32(w) / f32(h)

	glfw.SetWindowSizeCallback(window.handle, size_callback)

	glfw.MakeContextCurrent(window.handle)

	glodin.init(glfw.gl_set_proc_address)
}

window_uninit :: proc() {
	glodin.uninit()
	glfw.DestroyWindow(window.handle)
	glfw.Terminate()
}

callback_context: runtime.Context

@(private = "file")
size_callback :: proc "c" (window_handle: glfw.WindowHandle, width, height: i32) {
	window.width = max(int(width), 1)
	window.height = max(int(height), 1)
	window.aspect_ratio = f32(width) / f32(height)

	context = callback_context
	glodin.window_size_callback(int(width), int(height))
}

