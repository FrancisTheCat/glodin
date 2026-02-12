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
	destroy_uniform_buffer,
}

window_size_callback :: proc "contextless" (width, height: int) {
	root_fb.width = width
	root_fb.height = height

	gl.Viewport(0, 0, i32(width), i32(height))
	current_framebuffer = {}
}

@(private)
prev_window_size_callback: glfw.WindowSizeProc

init_glfw :: proc(window: glfw.WindowHandle, location := #caller_location) {
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
	init(glfw.gl_set_proc_address, location)

	w, h := glfw.GetWindowSize(window)
	window_size_callback(int(w), int(h))
}

init :: proc(set_proc_address: gl.Set_Proc_Address_Type, location := #caller_location) {
	framebuffer_data_allocator = context.allocator

	framebuffers     = new(type_of(framebuffers^    ))
	textures         = new(type_of(textures^        ))
	meshes           = new(type_of(meshes^          ))
	instanced_meshes = new(type_of(instanced_meshes^))
	programs         = new(type_of(programs^        ))
	computes         = new(type_of(computes^        ))
	uniform_buffers  = new(type_of(uniform_buffers^ ))

	gl.load_up_to(4, 6, set_proc_address)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

	logger_init()

	gl.Enable(gl.TEXTURE_CUBE_MAP_SEAMLESS)

	get_int :: proc(pname: u32) -> (value: int) {
		#assert(size_of(int) == size_of(int))
		gl.GetInteger64v(pname, cast(^i64)&value)
		return value
	}

	max_texture_size           = get_int(gl.MAX_TEXTURE_SIZE)
	max_texture_array_layers   = get_int(gl.MAX_ARRAY_TEXTURE_LAYERS)
	max_cube_map_size          = get_int(gl.MAX_CUBE_MAP_TEXTURE_SIZE)
	max_texture_max_anisotropy = get_int(gl.MAX_TEXTURE_MAX_ANISOTROPY)
	max_texture_units          = get_int(gl.MAX_TEXTURE_IMAGE_UNITS)

	// clamp this so we dont stack overflow when using alloca
	max_texture_units = min(max_texture_units, 128)

	texture_units = make([]Texture, max_texture_units)

	max_uniform_buffer_size        = get_int(gl.MAX_UNIFORM_BLOCK_SIZE)
	max_shader_storage_buffer_size = get_int(gl.MAX_SHADER_STORAGE_BLOCK_SIZE)

	debugf("max_texture_size: %v",               max_texture_size,               location = location)
	debugf("max_cube_map_size: %v",              max_cube_map_size,              location = location)
	debugf("max_texture_array_layers: %v",       max_texture_array_layers,       location = location)
	debugf("max_texture_max_anisotropy: %v",     max_texture_max_anisotropy,     location = location)
	debugf("max_texture_units: %v",              max_texture_units,              location = location)

	debugf("max_uniform_buffer_size: %M",        max_uniform_buffer_size,        location = location)
	debugf("max_shader_storage_buffer_size: %M", max_shader_storage_buffer_size, location = location)
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

	delete(framebuffers.free    )
	delete(textures.free        )
	delete(meshes.free          )
	delete(instanced_meshes.free)
	delete(programs.free        )
	delete(computes.free        )
	delete(uniform_buffers.free )

	free(framebuffers    )
	free(textures        )
	free(meshes          )
	free(instanced_meshes)
	free(programs        )
	free(computes        )
	free(uniform_buffers )

	delete(texture_units)

	logger_destroy()
}

