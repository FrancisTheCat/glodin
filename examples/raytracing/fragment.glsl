layout(location = 0) in  vec2 v_uv;

layout(location = 0) out vec4 f_color;

//----------------------------------------------------------------------------------------
//  1 out, 1 in...
float hash11(float p)
{
    p = fract(p * .1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}

//----------------------------------------------------------------------------------------
//  1 out, 2 in...
float hash12(vec2 p)
{
	vec3 p3  = fract(vec3(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

//----------------------------------------------------------------------------------------
//  1 out, 3 in...
float hash13(vec3 p3)
{
	p3  = fract(p3 * .1031);
    p3 += dot(p3, p3.zyx + 31.32);
    return fract((p3.x + p3.y) * p3.z);
}
//----------------------------------------------------------------------------------------
// 1 out 4 in...
float hash14(vec4 p4)
{
	p4 = fract(p4  * vec4(.1031, .1030, .0973, .1099));
    p4 += dot(p4, p4.wzxy+33.33);
    return fract((p4.x + p4.y) * (p4.z + p4.w));
}

//----------------------------------------------------------------------------------------
//  2 out, 1 in...
vec2 hash21(float p)
{
	vec3 p3 = fract(vec3(p) * vec3(.1031, .1030, .0973));
	p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx+p3.yz)*p3.zy);

}

//----------------------------------------------------------------------------------------
///  2 out, 2 in...
vec2 hash22(vec2 p)
{
	vec3 p3 = fract(vec3(p.xyx) * vec3(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx+33.33);
    return fract((p3.xx+p3.yz)*p3.zy);

}

//----------------------------------------------------------------------------------------
///  2 out, 3 in...
vec2 hash23(vec3 p3)
{
	p3 = fract(p3 * vec3(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx+33.33);
    return fract((p3.xx+p3.yz)*p3.zy);
}

//----------------------------------------------------------------------------------------
//  3 out, 1 in...
vec3 hash31(float p)
{
   vec3 p3 = fract(vec3(p) * vec3(.1031, .1030, .0973));
   p3 += dot(p3, p3.yzx+33.33);
   return fract((p3.xxy+p3.yzz)*p3.zyx); 
}


//----------------------------------------------------------------------------------------
///  3 out, 2 in...
vec3 hash32(vec2 p)
{
	vec3 p3 = fract(vec3(p.xyx) * vec3(.1031, .1030, .0973));
    p3 += dot(p3, p3.yxz+33.33);
    return fract((p3.xxy+p3.yzz)*p3.zyx);
}

//----------------------------------------------------------------------------------------
///  3 out, 3 in...
vec3 hash33(vec3 p3)
{
	p3 = fract(p3 * vec3(.1031, .1030, .0973));
    p3 += dot(p3, p3.yxz+33.33);
    return fract((p3.xxy + p3.yxx)*p3.zyx);

}

//----------------------------------------------------------------------------------------
// 4 out, 1 in...
vec4 hash41(float p)
{
	vec4 p4 = fract(vec4(p) * vec4(.1031, .1030, .0973, .1099));
    p4 += dot(p4, p4.wzxy+33.33);
    return fract((p4.xxyz+p4.yzzw)*p4.zywx);
    
}

//----------------------------------------------------------------------------------------
// 4 out, 2 in...
vec4 hash42(vec2 p)
{
	vec4 p4 = fract(vec4(p.xyxy) * vec4(.1031, .1030, .0973, .1099));
    p4 += dot(p4, p4.wzxy+33.33);
    return fract((p4.xxyz+p4.yzzw)*p4.zywx);

}

//----------------------------------------------------------------------------------------
// 4 out, 3 in...
vec4 hash43(vec3 p)
{
	vec4 p4 = fract(vec4(p.xyzx)  * vec4(.1031, .1030, .0973, .1099));
    p4 += dot(p4, p4.wzxy+33.33);
    return fract((p4.xxyz+p4.yzzw)*p4.zywx);
}

//----------------------------------------------------------------------------------------
// 4 out, 4 in...
vec4 hash44(vec4 p4)
{
	p4 = fract(p4  * vec4(.1031, .1030, .0973, .1099));
    p4 += dot(p4, p4.wzxy+33.33);
    return fract((p4.xxyz+p4.yzzw)*p4.zywx);
}

#define MAX_DISTANCE 1000
#define MAX_DEPTH    5
#define EPSILON      0.001

#define Sphere vec4

UNIFORM_BUFFER(u_spheres,   Sphere,  MAX_SPHERES  );
UNIFORM_BUFFER(u_materials, vec4,    MAX_SPHERES  );
UNIFORM_BUFFER(u_bvh_nodes, ivec2,   MAX_BVH_NODES);
UNIFORM_BUFFER(u_bvh_aabbs, vec4[2], MAX_BVH_NODES);

uniform int         u_n_spheres;
uniform int         u_noise_source;
uniform vec2        u_inv_resolution;
uniform vec3        u_camera_position = vec3(0, 0, 30);
uniform mat3        u_camera_rotation_matrix;
uniform float       u_aspect_ratio;
uniform samplerCube u_skybox;

struct Ray {
    vec3 origin;
    vec3 direction;
};

float noise_source = float(u_noise_source);

float rand() {
    noise_source += 1;
    return hash12(vec2(v_uv * 1000) + float(noise_source));
}

vec3 rand_vec3() {
    return normalize(
        vec3(
            2 * rand() - 1,
            2 * rand() - 1,
            2 * rand() - 1
        )
    );
}

float ray_sphere_hit(Ray r, Sphere s, float t_max, out vec3 position, out vec3 normal) {
    vec3 o = r.origin - s.xyz;

    float a = dot(r.direction, r.direction);
    float b = 2 * dot(r.direction, o);
    float c = dot(o, o) - s.w * s.w;

    float d = b * b - 4 * a * c;

    if (d < 0) {
        return -1;
    }

    float distance = (-b - sqrt(d)) / (2 * a);

    if (distance < EPSILON || distance > t_max) {
        return -1;
    }

    position = r.origin + r.direction * distance;
    normal   = (position - s.xyz) / s.w;

    return distance;
}

bool ray_aabb_hit(Ray r, vec4 aabb[2], float t_min, float t_max) {
    float tx1 = (aabb[0].x - r.origin.x)/r.direction.x;
    float tx2 = (aabb[1].x - r.origin.x)/r.direction.x;

    float tmin = min(tx1, tx2);
    float tmax = max(tx1, tx2);

    float ty1 = (aabb[0].y - r.origin.y)/r.direction.y;
    float ty2 = (aabb[1].y - r.origin.y)/r.direction.y;

    tmin = max(tmin, min(ty1, ty2));
    tmax = min(tmax, max(ty1, ty2));

    float tz1 = (aabb[0].z - r.origin.z)/r.direction.z;
    float tz2 = (aabb[1].z - r.origin.z)/r.direction.z;

    tmin = max(tmin, min(tz1, tz2));
    tmax = min(tmax, max(tz1, tz2));

    return tmax >= tmin;
}

// no recursion :(
float ray_bvh_hit(Ray r, out vec3 position, out vec3 normal, out int material_id) {
    int count = 0;
    float closest_distance = MAX_DISTANCE;
    int   potential_nodes[64];
    int   n_nodes = 1;
    potential_nodes[0] = 0;

    vec3 current_position;
    vec3 current_normal;

    while (n_nodes != 0) {
        int current = potential_nodes[n_nodes - 1];
        n_nodes -= 1;
        if (current > 0) {
            if (current < MAX_SPHERES) {
                count += 1;
                Sphere s = u_spheres[current - 1];
                float current_distance = ray_sphere_hit(
                    r,
                    s,
                    closest_distance,
                    current_position,
                    current_normal
                );
                if (current_distance > 0) {
                    closest_distance = current_distance;
                    position         = current_position;
                    normal           = current_normal;
                    material_id      = current - 1;
                }
            }
        } else {
            current = -current;
            if (ray_aabb_hit(r, u_bvh_aabbs[current], EPSILON, closest_distance)) {
                if (n_nodes + 2 <= potential_nodes.length()) {
                    potential_nodes[n_nodes] = u_bvh_nodes[current][0]; n_nodes += 1;
                    potential_nodes[n_nodes] = u_bvh_nodes[current][1]; n_nodes += 1;
                }
            }
        }
    }

    return closest_distance != MAX_DISTANCE ? closest_distance : -1;
}

float ray_scene_hit(Ray r, out vec3 position, out vec3 normal) {
    float closest_distance = MAX_DISTANCE;
    for (int i = 0; i < min(MAX_SPHERES, u_n_spheres); i += 1) {
        Sphere s = u_spheres[i];
        vec3  current_position;
        vec3  current_normal;
        float current_distance = ray_sphere_hit(r, s, closest_distance, current_position, current_normal);
        if (current_distance > 0) {
            closest_distance = current_distance;
            position         = current_position;
            normal           = current_normal;
        }
    }

    return closest_distance != MAX_DISTANCE ? closest_distance : -1;
}

Ray get_ray(vec2 uv) {
    Ray r;
    r.origin = u_camera_position;
    uv = uv * 2 - 1;
    uv.x *= u_aspect_ratio;
    uv.x += (rand() * 2 - 1) * u_inv_resolution.x;
    uv.y += (rand() * 2 - 1) * u_inv_resolution.y;
    r.direction = u_camera_rotation_matrix * normalize(vec3(uv, -1));
    return r;
}

vec3 sample_sky_color(vec3 direction) {
    return texture(u_skybox, direction).rgb;
}

void main() {
    Ray r = get_ray(v_uv);
    vec3 accumulated_tint = vec3(1);
    vec3 position, normal;
    float distance;
    int material_id;

    for (int depth = 0; depth < MAX_DEPTH; depth += 1) {
        distance = ray_bvh_hit(r, position, normal, material_id);
        if (distance > 0) {
            vec4 material = u_materials[material_id];
            if (material.w < 0) {
                r.direction = normalize(normal + rand_vec3());
            } else {
                r.direction = reflect(r.direction, normal) + material.w * rand_vec3();
            }
            r.origin          = position + normal * EPSILON;
            accumulated_tint *= material.rgb;
        } else  {
            if (depth == MAX_DEPTH - 1) {
                accumulated_tint = vec3(0);
            }
            break;
        }
    }
    f_color.rgb = sample_sky_color(r.direction) * accumulated_tint;
}
