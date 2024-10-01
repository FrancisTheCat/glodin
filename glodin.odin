package glodin

import "base:runtime"

import gl "vendor:OpenGL"
import "vendor:glfw"

GLODIN_TRACK_LEAKS :: #config(GLODIN_TRACK_LEAKS, ODIN_DEBUG)

Source_Code_Location :: runtime.Source_Code_Location

@(private)
get_handle :: proc {
	get_program_handle,
	get_compute_handle,
	get_texture_handle,
	get_framebuffer_handle,
}

_get_handle :: proc(x: $T) -> u32 {
	return get_handle(x)
}

destroy :: proc {
	destroy_mesh,
	destroy_instanced_mesh,
	destroy_program,
	destroy_framebuffer,
	destroy_texture,
	destroy_compute,
}

window_size_callback :: proc "contextless" (width, height: int) {
	root_fb.width = width
	root_fb.height = height

	gl.Viewport(0, 0, i32(width), i32(height))
	current_framebuffer = {}
}

@(private)
prev_window_size_callback: glfw.WindowSizeProc

init_glfw :: proc(window: glfw.WindowHandle) {
	prev_window_size_callback = glfw.SetWindowSizeCallback(
		window,
		proc "c" (window: glfw.WindowHandle, width, height: i32) {
			window_size_callback(int(width), int(height))
			if prev_window_size_callback != nil {
				prev_window_size_callback(window, width, height)
			}
		},
	)

	glfw.MakeContextCurrent(window)
	init(glfw.gl_set_proc_address)
}

init :: proc(set_proc_address: gl.Set_Proc_Address_Type) {
	program_data_allocator = context.allocator

	framebuffers = new(type_of(framebuffers^))
	textures = new(type_of(textures^))
	meshes = new(type_of(meshes^))
	instanced_meshes = new(type_of(instanced_meshes^))
	programs = new(type_of(programs^))
	computes = new(type_of(computes^))

	gl.load_up_to(4, 5, set_proc_address)

	logger_init()
	textures_init()
}

uninit :: proc() {
	when GLODIN_TRACK_LEAKS {
		iter: int
		for _, fb in ga_iter(framebuffers, &iter) {
			warnf("fb %v was not destroyed", fb)
		}

		iter = 0
		for _, tex in ga_iter(textures, &iter) {
			warnf("tex %v was not destroyed", tex)
		}

		iter = 0
		for _, mesh in ga_iter(meshes, &iter) {
			warnf("mesh %v was not destroyed", mesh)
		}

		iter = 0
		for _, instanced_mesh in ga_iter(instanced_meshes, &iter) {
			warnf("instanced_mesh %v was not destroyed", instanced_mesh)
		}

		iter = 0
		for _, program in ga_iter(programs, &iter) {
			warnf("program %v was not destroyed", program)
		}

		iter = 0
		for _, compute in ga_iter(computes, &iter) {
			warnf("compute %v was not destroyed", compute)
		}
	}
}

