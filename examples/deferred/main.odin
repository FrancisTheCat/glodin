package example

import "base:runtime"

import "core:log"
@(require)
import "core:image/png"
import la "core:math/linalg"
import glm "core:math/linalg/glsl"
import "core:strings"
import "core:time"

import "vendor:glfw"

import glodin "../.."

program: glodin.Program
program_post: glodin.Program

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

	meshes := glodin.create_mesh(#load("cube.glb"), "cube.glb") or_else panic("Failed to load mesh")
	defer for mesh in meshes do glodin.destroy(mesh)
	cube := meshes[0]

	program = glodin.create_program_source(
		#load("shaders/vertex.glsl"),
		#load("shaders/fragment.glsl"),
	) or_else panic("Failed to compile program")
	defer glodin.destroy(program)

	program_post = glodin.create_program_source(
		#load("shaders/post/vertex.glsl"),
		#load("shaders/post/fragment.glsl"),
	) or_else panic("Failed to compile program")
	defer glodin.destroy(program_post)

	start_time := time.now()

	albedo_texture := glodin.create_texture(#load("../textured_cube/texture.png"), "../textured_cube/texture.png") or_else panic("")
	defer glodin.destroy_texture(albedo_texture)
	glodin.set_texture_sampling_state(albedo_texture, .Nearest)
	glodin.set_uniform(program, "u_albedo_texture", albedo_texture)

	total_time: f64
	for !window.should_close {
		_time := f64(time.duration_seconds(time.since(start_time)))
		total_time = _time

		glodin.clear_color(g_buffer.framebuffer, 0, 0)
		glodin.clear_color(g_buffer.framebuffer, 0, 1)
		glodin.clear_color(g_buffer.framebuffer, 0, 2)
		glodin.clear_color(g_buffer.framebuffer, 0, 3)
		glodin.clear_color(g_buffer.framebuffer, 0, 4)
		glodin.clear_depth(g_buffer.framebuffer, 1)

		glodin.enable(.Depth_Test, .Cull_Face)

		update_camera()
		glodin.set_uniforms(program, {
			{ "u_view",        camera.view,        },
			{ "u_perspective", camera.perspective, },
		})

		glodin.set_uniforms(program, {
			{ "u_model", glm.mat4Translate(RIGHT * 3) * glm.mat4Rotate(UP + RIGHT + FORWARD, 3 + f32(total_time)), },
			{ "u_color", glm.vec3{1, 0, 0},                                                                        },
		})
		glodin.draw(g_buffer.framebuffer, program, cube)

		glodin.set_uniforms(program, {
			{ "u_model", glm.mat4Rotate(UP + FORWARD, 1 + f32(total_time)), },
			{ "u_color", glm.vec3{0, 1, 0},                                 },
			},
		)
		glodin.draw(g_buffer.framebuffer, program, cube)

		glodin.set_uniforms(program, {
			{ "u_model", glm.mat4Translate(LEFT * 3) * glm.mat4Rotate(UP + LEFT + FORWARD, -5 + f32(total_time)), },
			{ "u_color", glm.vec3{0, 0, 1},                                                                       },
		})
		glodin.draw(g_buffer.framebuffer, program, cube)

		glodin.set_uniform(program_post, "u_camera_position", camera.position)
		glodin.set_uniforms_from_struct(program_post, g_buffer)
		glodin.disable(.Depth_Test, .Cull_Face)
		glodin.draw({}, program_post, quad)

		window_poll()
	}

	g_buffer_uninit()
}

g_buffer: G_Buffer

G_Buffer :: struct {
	framebuffer:      glodin.Framebuffer `glodin-uniform:"-"`,
	depth_texture:    glodin.Texture     `glodin-uniform:"-"`,
	position_texture: glodin.Texture     `glodin-uniform:"u_texture_position"`,
	normal_texture:   glodin.Texture     `glodin-uniform:"u_texture_normal"`,
	albedo_texture:   glodin.Texture     `glodin-uniform:"u_texture_albedo"`,
}

g_buffer_init :: proc() {
	g_buffer.position_texture = glodin.create_texture_empty(window.width, window.height, .RGB32F)
	g_buffer.normal_texture   = glodin.create_texture_empty(window.width, window.height, .RGB32F)
	g_buffer.albedo_texture   = glodin.create_texture_empty(window.width, window.height, .RGB32F)

	g_buffer.depth_texture    = glodin.create_texture_empty(window.width, window.height, .Depth32f)

	g_buffer.framebuffer      = glodin.create_framebuffer(
		{
			g_buffer.position_texture,
			g_buffer.normal_texture,
			g_buffer.albedo_texture,
		},
		g_buffer.depth_texture,
	)
}

g_buffer_uninit :: proc() {
	glodin.destroy(g_buffer.position_texture)
	glodin.destroy(g_buffer.normal_texture)
	glodin.destroy(g_buffer.albedo_texture)
	glodin.destroy(g_buffer.depth_texture)

	glodin.destroy(g_buffer.framebuffer)
}

g_buffer_resize :: proc() {
	g_buffer_uninit()
	g_buffer_init()
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
	g_buffer_init()

	glfw.SwapInterval(0)

	recompute_perspective()
}

window_uninit :: proc() {
	glodin.uninit()
	glfw.DestroyWindow(window.handle)
	glfw.Terminate()
}

callback_context: runtime.Context

@(private = "file")
size_callback :: proc "c" (window_handle: glfw.WindowHandle, width, height: i32) {
	window.width  = max(int(width),  1)
	window.height = max(int(height), 1)
	window.aspect_ratio = f32(width) / f32(height)

	context = callback_context
	g_buffer_resize()
	recompute_perspective()
	glodin.window_size_callback(int(width), int(height))
}

// odinfmt: disable
UP       :: glm.vec3{+0, +1, +0}
DOWN     :: glm.vec3{+0, -1, +0}
FORWARD  :: glm.vec3{+0, +0, -1}
BACKWARD :: glm.vec3{+0, +0, +1}
LEFT     :: glm.vec3{+1, +0, +0}
RIGHT    :: glm.vec3{-1, +0, +0}
// odinfmt: enable

camera: Camera = {
	position = BACKWARD * 5,
	near     = 0.01,
	far      = 1000,
	fov      = 1,
}

Camera :: struct {
	perspective:        glm.mat4,
	view:               glm.mat4,
	position:           glm.vec3,
	forward, up, right: glm.vec3,
	near, far, fov:     f32,
	yaw, pitch:         f32,
}

update_camera :: proc() {
	camera.forward = (get_camera_rotation_matrix() * glm.vec4{0, 0, -1, 0}).xyz
	camera.right = glm.cross(camera.forward, UP)
	camera.up = glm.cross(camera.right, camera.forward)
	recompute_view()
}

get_camera_rotation_matrix :: proc() -> glm.mat4 {
	return la.matrix4_from_euler_angles_f32(
		glm.clamp(camera.pitch, -glm.PI * 0.5, glm.PI * 0.5),
		camera.yaw,
		0,
		.ZYX,
	)
}

recompute_perspective :: proc "contextless" () {
	camera.perspective = glm.mat4Perspective(
		camera.fov,
		window.aspect_ratio,
		camera.near,
		camera.far,
	)
}

recompute_view :: proc() {
	camera.view = glm.mat4LookAt(
		camera.position,
		camera.position + camera.forward,
		glm.vec3{0, 1, 0},
	)
}

