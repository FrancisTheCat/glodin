#version 450

//////////////////////////////////////////////////////////////////////
//
// Visualizing Björn Ottosson's "oklab" colorspace
//
// shadertoy implementation by mattz
//
// license CC0 (public domain)
// https://creativecommons.org/share-your-work/public-domain/cc0/
//
// Click and drag to set lightness (mouse x) and chroma (mouse y).
// Hue varies linearly across the image from left to right.
//
// While mouse is down, plotted curves show oklab components
// L (red), a (green), and b (blue). 
//
// To test the inverse mapping, the plotted curves are generated
// by mapping the (pre-clipping) linear RGB color back to oklab 
// space.
//
// White bars on top of the image (and black bars on the bottom of
// the image) indicate clipping when one or more of the R, G, B 
// components are greater than 1.0 (or less than 0.0 respectively).
//
// The color accompanying the black/white bar shows which channels
// are out of gamut.
//
// Click in the bottom left to reset the view.
//
// Hit the 'G' key to toggle displaying a gamut test:
//
//   * black pixels indicate that RGB values for some hues
//     were clipped to 0 at the given lightness/chroma pair.
//
//   * white pixels indicate that RGB values for some hues
//     were clipped to 1 at the given lightness/chroma pair
//
//   * gray pixels indicate that both types of clipping happened
//
// Hit the 'U' key to display a uniform sampling of linear sRGB 
// space, converted into oklab lightness (x position) and chroma
// (y position) coordinates. If you mouse over a colored dot, the
// spectrum on screen should include that exact color.
//
//////////////////////////////////////////////////////////////////////

//////////////////////////////////////////////////////////////////////
// sRGB color transform and inverse from 
// https://bottosson.github.io/posts/colorwrong/#what-can-we-do%3F

vec3 srgb_from_linear_srgb(vec3 x) {

    vec3 xlo = 12.92*x;
    vec3 xhi = 1.055 * pow(x, vec3(0.4166666666666667)) - 0.055;
    
    return mix(xlo, xhi, step(vec3(0.0031308), x));

}

vec3 linear_srgb_from_srgb(vec3 x) {

    vec3 xlo = x / 12.92;
    vec3 xhi = pow((x + 0.055)/(1.055), vec3(2.4));
    
    return mix(xlo, xhi, step(vec3(0.04045), x));

}

//////////////////////////////////////////////////////////////////////
// oklab transform and inverse from
// https://bottosson.github.io/posts/oklab/


const mat3 fwdA = mat3(1.0, 1.0, 1.0,
                       0.3963377774, -0.1055613458, -0.0894841775,
                       0.2158037573, -0.0638541728, -1.2914855480);
                       
const mat3 fwdB = mat3(4.0767245293, -1.2681437731, -0.0041119885,
                       -3.3072168827, 2.6093323231, -0.7034763098,
                       0.2307590544, -0.3411344290,  1.7068625689);

const mat3 invB = mat3(0.4121656120, 0.2118591070, 0.0883097947,
                       0.5362752080, 0.6807189584, 0.2818474174,
                       0.0514575653, 0.1074065790, 0.6302613616);
                       
const mat3 invA = mat3(0.2104542553, 1.9779984951, 0.0259040371,
                       0.7936177850, -2.4285922050, 0.7827717662,
                       -0.0040720468, 0.4505937099, -0.8086757660);

vec3 oklab_from_linear_srgb(vec3 c) {

    vec3 lms = invB * c;
            
    return invA * (sign(lms)*pow(abs(lms), vec3(0.3333333333333)));
    
}

vec3 linear_srgb_from_oklab(vec3 c) {

    vec3 lms = fwdA * c;
    
    return fwdB * (lms * lms * lms);
    
}

//////////////////////////////////////////////////////////////////////

in vec2 v_tex_coords;

layout(location = 0) out vec4 f_color;

uniform float u_time;
uniform float u_aspect;
uniform vec2  u_inv_resolution;

#define Cmplx vec2

Cmplx cmul(Cmplx a, Cmplx b) {
    return vec2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

float fractal(vec2 coord) {
    Cmplx c = Cmplx(-0.4, 0.6) + 0.001 * vec2(sin(u_time));
    Cmplx z = 3 * (coord - 0.5);

    float i = 0;
    while (i < 255 && length(z) < 2) {
        z = cmul(z, z) + c;
        i += 1;
    }

    float t = (i - log2(max(length(z), 1))) / 256.0;

    return t;
}

vec2 hash21(float p)
{
	vec3 p3 = fract(vec3(p) * vec3(.1031, .1030, .0973));
	p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx+p3.yz)*p3.zy);

}

void main() {
    float angle = u_time * 10;
    vec2 c = (v_tex_coords * 2 - 1) * 0.5;
    c.x *= u_aspect;

    // float section = round(c.x * 10);
    // c.y += sin(u_time + section) * 0.05;

    angle = 0;

    vec2 coord;
    coord.x = sin(angle) * c.x + cos(angle) * c.y;
    coord.y = sin(angle) * c.y - cos(angle) * c.x;
    
    float fractal_sample = 0;
    for (int i = 0; i < 16; i += 1) {
        fractal_sample += fractal(c * 0.5 + 0.5 + 0.5 * hash21(float(i)) * u_inv_resolution) / 16.0;
    }
    
    // setup oklab color
    float theta = 2.*3.141592653589793 * fract(u_time + fractal_sample);

    float L      = 0.8;
    float chroma = 0.2;
    
    float a = chroma*cos(theta);
    float b = chroma*sin(theta);
    
    vec3 lab = vec3(L, a, b);

    // convert to rgb 
    vec3 rgb = linear_srgb_from_oklab(lab);

    // clamp into rgb color cube
    rgb = clamp(rgb, 0.0, 1.0);

    f_color.rgb = vec3(fractal_sample);
    f_color.a = 1;
}
