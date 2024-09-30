package glodin

import gl "vendor:OpenGL"

@(private)
Texture_Sampling_Parameters :: struct {
	mag_filter:   Texture_Mag_Filter,
	min_filter:   Texture_Min_Filter,
	wrap:         [2]Texture_Wrap,
	border_color: [4]f32,
	anisotropy:   f32,
}

Sampler :: distinct Index

@(private = "file")
samplers: ^Generational_Array(_Sampler)

@(private)
get_sampler :: proc(sampler: Sampler) -> ^_Sampler {
	return ga_get(samplers, sampler)
}

@(private)
get_sampler_texture :: proc(sampler: Sampler) -> Texture {
	return ga_get(samplers, sampler).texture
}

_get_sampler_handle :: proc(sampler: Sampler) -> Texture {
	return get_sampler_texture(sampler)
}

@(private)
_Sampler :: struct {
	handle:  u32,
	texture: Texture,
	using _: Texture_Sampling_Parameters,
}

create_sampler :: proc(
	texture: Texture,
	mag_filter: Texture_Mag_Filter = .Linear,
	min_filter: Texture_Min_Filter = .Nearest_Mipmap_Linear,
	wrap: [2]Texture_Wrap = {},
	border_color: [4]f32 = {},
	anisotropy: f32,
	location := #caller_location,
) -> Sampler {
	s: _Sampler = {
		texture      = texture,
		mag_filter   = mag_filter,
		min_filter   = min_filter,
		wrap         = wrap,
		border_color = border_color,
		anisotropy   = anisotropy,
	}

	gl.CreateSamplers(1, &s.handle)

	for w, direction in wrap {
		if w != s.wrap[direction] {
			gl.TextureParameteri(
				s.handle,
				GL_TEXTURE_WRAP_DIRECTION[direction],
				GL_TEXTURE_WRAP[w],
			)
		}
	}

	gl.SamplerParameteri(s.handle, gl.TEXTURE_MAG_FILTER, i32(mag_filter))
	gl.SamplerParameteri(s.handle, gl.TEXTURE_MIN_FILTER, i32(min_filter))

	border_color := border_color
	gl.SamplerParameterfv(s.handle, gl.TEXTURE_BORDER_COLOR, &border_color[0])

	gl.SamplerParameterf(s.handle, gl.TEXTURE_MAX_ANISOTROPY, anisotropy)

	return Sampler(ga_append(samplers, s))
}

