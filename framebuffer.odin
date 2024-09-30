// TODO(Franz):
// - improve support for changing dimensions
// - multiple color targets
package glodin

import gl "vendor:OpenGL"

@(private)
root_fb: _Framebuffer

@(private)
framebuffers: ^Generational_Array(_Framebuffer)

Framebuffer :: distinct Index

@(private)
get_framebuffer :: proc(framebuffer: Framebuffer) -> ^_Framebuffer {
	if framebuffer == {} {
		return &root_fb
	}
	fb := ga_get(framebuffers, framebuffer)
	if fb == nil {
		debugf("Framebuffer %v not found", framebuffer)
	}
	return fb
}

@(private)
get_framebuffer_handle :: proc(framebuffer: Framebuffer) -> u32 {
	if framebuffer == {} {
		return 0
	}
	fb := ga_get(framebuffers, framebuffer)
	return fb.handle
}

_get_framebuffer_handle :: proc(framebuffer: Framebuffer) -> u32 {
	fb := ga_get(framebuffers, framebuffer)
	return fb.handle
}

@(private)
_Framebuffer :: struct {
	color_texture:   Maybe(Texture),
	depth_texture:   Maybe(Texture),
	stencil_texture: Maybe(Texture),
	width, height:   int,
	samples:         int,
	handle:          u32,
	depth_stencil:   bool,
}

create_framebuffer :: proc(
	color_texture: Maybe(Texture),
	depth_texture: Maybe(Texture) = nil,
	stencil_texture: Maybe(Texture) = nil,
	location := #caller_location,
) -> (
	framebuffer: Framebuffer,
	ok: bool,
) {
	fb: _Framebuffer
	gl.CreateFramebuffers(1, &fb.handle)

	dimensions_resolved: bool

	color: {
		ct := get_texture(color_texture.? or_break color)
		assert(!is_depth_format(ct.format) && (ct.format != .Stencil8))
		fb.width = ct.width
		fb.height = ct.height

		gl.NamedFramebufferTexture(fb.handle, gl.COLOR_ATTACHMENT0, ct.handle, 0)

		dimensions_resolved = true
	}

	fb.color_texture = color_texture
	fb.depth_texture = depth_texture
	fb.stencil_texture = stencil_texture

	if d, ok := depth_texture.?; ok {
		d := get_texture(d)

		if !dimensions_resolved {
			fb.width = d.width
			fb.height = d.height
			dimensions_resolved = true
		}

		assert(d != nil, "Depth texture attached to framebuffer is invalid", location = location)
		assert(
			d.width == fb.width && d.height == fb.height,
			"Framebuffer textures have to have the same dimensions",
		)
		assert(is_depth_format(d.format))
		if is_depth_stencil_format(d.format) {
			gl.NamedFramebufferTexture(fb.handle, gl.DEPTH_STENCIL_ATTACHMENT, d.handle, 0)
			fb.depth_stencil = true
			fb.stencil_texture = depth_texture
		} else {
			gl.NamedFramebufferTexture(fb.handle, gl.DEPTH_ATTACHMENT, d.handle, 0)
		}
	}
	stencil: if s, ok := stencil_texture.?; ok {
		if fb.depth_stencil {
			warn(
				"Depth texture format include stencil, which will be ignored since an explicit stencil texture was provided",
				location = location,
			)
		}
		s := get_texture(s)
		if !dimensions_resolved {
			fb.width = s.width
			fb.height = s.height
			dimensions_resolved = true
		}
		assert(is_depth_stencil_format(s.format) || s.format == .Stencil8)
		assert(
			s.width == fb.width && s.height == fb.height,
			"Framebuffer textures have to have the same dimensions",
		)
		if is_depth_stencil_format(s.format) {
			warn(
				"Combined stencil and depth textures should be passed in as depth attachment",
				location = location,
			)
			fb.depth_stencil = false
			fb.stencil_texture = stencil_texture
		}
		gl.NamedFramebufferTexture(fb.handle, gl.STENCIL_ATTACHMENT, s.handle, 0)
	}
	return cast(Framebuffer)ga_append(framebuffers, fb), true
}

set_framebuffer_color_texture :: proc(framebuffer: Framebuffer, texture: Texture) {
	framebuffer := get_framebuffer(framebuffer)
	tex := get_texture(texture)
	assert(!is_depth_format(tex.format) && (tex.format != .Stencil8))
	if framebuffer.width != tex.width || framebuffer.height != tex.height {
		// panic("Wrong texture size for framebuffer")
		gl.Viewport(0, 0, i32(tex.width), i32(tex.height))
		framebuffer.width = tex.width
		framebuffer.height = tex.height
	} // else 
	{
		gl.NamedFramebufferTexture(framebuffer.handle, gl.COLOR_ATTACHMENT0, tex.handle, 0)
		framebuffer.color_texture = texture
	}
}

set_framebuffer_depth_texture :: proc(framebuffer: Framebuffer, texture: Texture) {
	framebuffer := get_framebuffer(framebuffer)
	tex := get_texture(texture)
	assert(is_depth_format(tex.format))
	if framebuffer.width != tex.width || framebuffer.height != tex.height {
		panic("Wrong texture size for framebuffer")
	} else {
		gl.NamedFramebufferTexture(framebuffer.handle, gl.DEPTH_ATTACHMENT, tex.handle, 0)
		framebuffer.depth_texture = texture
	}
}

set_framebuffer_stencil_texture :: proc(framebuffer: Framebuffer, texture: Texture) {
	framebuffer := get_framebuffer(framebuffer)
	tex := get_texture(texture)
	assert(tex.format == .Stencil8 || is_depth_stencil_format(tex.format))
	if framebuffer.width != tex.width || framebuffer.height != tex.height {
		panic("Wrong texture size for framebuffer")
	} else {
		gl.NamedFramebufferTexture(framebuffer.handle, gl.STENCIL_ATTACHMENT, tex.handle, 0)
		framebuffer.stencil_texture = texture
	}
}

set_framebuffer_depth_stencil_texture :: proc(framebuffer: Framebuffer, texture: Texture) {
	framebuffer := get_framebuffer(framebuffer)
	tex := get_texture(texture)
	assert(is_depth_stencil_format(tex.format))
	if framebuffer.width != tex.width || framebuffer.height != tex.height {
		panic("Wrong texture size for framebuffer")
	} else {
		gl.NamedFramebufferTexture(framebuffer.handle, gl.DEPTH_STENCIL_ATTACHMENT, tex.handle, 0)
		framebuffer.stencil_texture = texture
		framebuffer.depth_texture = texture
	}
}

destroy_framebuffer :: #force_inline proc(framebuffer: Framebuffer) {
	f := get_framebuffer(framebuffer).handle
	gl.DeleteFramebuffers(1, &f)

	ga_remove(framebuffers, framebuffer)
}

Rect :: struct {
	min, max: [2]int,
}

blit_framebuffers :: proc {
	blit_framebuffer_regions,
	blit_entire_framebuffer,
}

get_framebuffer_size :: proc(fb: Framebuffer) -> (width, height: int) {
	if fb == 0 {
		return root_fb.width, root_fb.height
	}
	fb := get_framebuffer(fb)
	return fb.width, fb.height
}

blit_entire_framebuffer :: proc(dst, src: Framebuffer, filter: Texture_Mag_Filter = .Nearest) {
	src_rect, dst_rect: Rect
	src_rect.max.x, src_rect.max.y = get_framebuffer_size(src)
	dst_rect.max.x, dst_rect.max.y = get_framebuffer_size(dst)
	blit_framebuffer_regions(dst, src, dst_rect, src_rect, filter)
}

blit_framebuffer_regions :: proc(
	dst, src: Framebuffer,
	dst_rect: Rect,
	src_rect: Rect,
	filter: Texture_Mag_Filter = .Nearest,
) {
	gl.BlitNamedFramebuffer(
		get_framebuffer_handle(src),
		get_framebuffer_handle(dst),
		i32(src_rect.min.x),
		i32(src_rect.min.y),
		i32(src_rect.max.x),
		i32(src_rect.max.y),
		i32(dst_rect.min.x),
		i32(dst_rect.min.y),
		i32(dst_rect.max.x),
		i32(dst_rect.max.y),
		gl.COLOR_BUFFER_BIT,
		u32(filter),
	)
}

