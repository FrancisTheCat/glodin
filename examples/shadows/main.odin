package shadows

import "base:runtime"

import "core:log"
import la "core:math/linalg"
import glm "core:math/linalg/glsl"
import "core:time"

import "vendor:glfw"

import glodin "../.."

main :: proc() {
	window_init()
	defer window_uninit()

	cube := (glodin.create_mesh(#load("cube.glb"), "cube.glb") or_else panic("failed to load cube mesh"))[0]
	defer glodin.destroy(cube)

	program := glodin.create_program_source(#load("vertex.glsl"), #load("fragment.glsl")) or_else panic(
		"failed to load program",
	)
	defer glodin.destroy(program)

	shadow_program := glodin.create_program_source(#load("vertex.glsl"), #load("shadow.glsl")) or_else panic(
		"failed to load program",
	)
	defer glodin.destroy(shadow_program)

	glodin.enable(.Depth_Test, .Cull_Face)

	shadow_map := glodin.create_texture(
		1024,
		1024,
		format = .Depth24,
		mag_filter = .Nearest,
		min_filter = .Nearest,
		wrap = glodin.Texture_Wrap.Clamp_To_Border,
		border_color = 1,
	)
	defer glodin.destroy(shadow_map)

	shadow_fb := glodin.create_framebuffer(color_textures = {}, depth_texture = shadow_map)
	defer glodin.destroy(shadow_fb)

	start_time := time.now()

	for !window.should_close {
		t := f32(time.duration_seconds(time.since(start_time)))

		light_direction := glm.normalize(UP * 2 + glm.vec3{glm.sin(t), 0, glm.cos(t)})
		shadow_view_matrix := glm.mat4LookAt(light_direction * 5, 0, UP)
		shadow_proj_matrix := glm.mat4Ortho3d(-3, 3, -3, 3, 1, 20)

		Mesh :: struct {
			mesh:      glodin.Mesh,
			transform: glm.mat4,
		}

		meshes := []Mesh {
			{mesh = cube, transform = glm.mat4Translate(DOWN * 2) * glm.mat4Scale({4, 1, 4})},
			{
				mesh = cube,
				transform = glm.mat4Translate(UP + LEFT) *
				glm.mat4Rotate(UP + RIGHT, t) *
				glm.mat4Scale(0.5),
			},
			{
				mesh = cube,
				transform = glm.mat4Translate(UP + RIGHT) *
				glm.mat4Rotate(UP + RIGHT, -t + 1) *
				glm.mat4Scale(0.5),
			},
		}

		draw_meshes :: proc(fb: glodin.Framebuffer, program: glodin.Program, meshes: []Mesh) {
			for mesh in meshes {
				glodin.set_uniforms(program, {{"u_model", mesh.transform}})
				glodin.draw_mesh(fb, program, mesh.mesh)
			}
		}

		glodin.clear_depth(shadow_fb, 1)
		glodin.set_uniforms(
			shadow_program,
			{{"u_view", shadow_view_matrix}, {"u_perspective", shadow_proj_matrix}},
		)
		draw_meshes(shadow_fb, shadow_program, meshes)

		glodin.clear_color(0, 0.1)
		glodin.clear_depth(0, 1)

		update_camera()
		glodin.set_uniforms(
			program,
			{
				{"u_view", camera.view},
				{"u_perspective", camera.perspective},
				{"u_depth_texture", shadow_map},
				{"u_shadow_matrix", shadow_proj_matrix * shadow_view_matrix},
				{"u_light_direction", light_direction},
			},
		)
		draw_meshes(0, program, meshes)

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

	glfw.SwapInterval(0)

	recompute_perspective()
}

window_uninit :: proc() {
	glodin.uninit()
	glfw.DestroyWindow(window.handle)
	glfw.Terminate()
}

callback_context: runtime.Context

size_callback :: proc "c" (window_handle: glfw.WindowHandle, width, height: i32) {
	window.width = max(int(width), 1)
	window.height = max(int(height), 1)
	window.aspect_ratio = f32(width) / f32(height)

	context = callback_context
	recompute_perspective()
	glodin.window_size_callback(int(width), int(height))
}

UP :: glm.vec3{+0, +1, +0}
DOWN :: glm.vec3{+0, -1, +0}
FORWARD :: glm.vec3{+0, +0, -1}
BACKWARD :: glm.vec3{+0, +0, +1}
LEFT :: glm.vec3{+1, +0, +0}
RIGHT :: glm.vec3{-1, +0, +0}

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
	camera.pitch = glm.clamp(camera.pitch, -glm.PI * 0.5, glm.PI * 0.5)
	camera.forward = (get_camera_rotation_matrix() * glm.vec4{0, 0, -1, 0}).xyz
	camera.right = glm.cross(camera.forward, UP)
	camera.up = glm.cross(camera.right, camera.forward)

	recompute_view()
}

get_camera_rotation_matrix :: proc() -> glm.mat4 {
	return la.matrix4_from_euler_angles_f32(camera.pitch, camera.yaw, 0, .ZYX)
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

