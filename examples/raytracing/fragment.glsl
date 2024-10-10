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
#define MAX_DEPTH    8
#define EPSILON      0.005

#define Sphere vec4

UNIFORM_BUFFER(u_spheres,   Sphere,  MAX_SPHERES  );
UNIFORM_BUFFER(u_materials, vec4[2], MAX_SPHERES  );
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

struct Hit {
    vec3  position;
    vec3  normal;
    float distance;
    int   material_id;
    bool  back_face;
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

bool ray_sphere_hit(Ray r, Sphere s, float t_max, out Hit hit) {
    bool back_face = false;
    vec3 o = r.origin - s.xyz;

    float a = dot(r.direction, r.direction);
    float b = 2 * dot(r.direction, o);
    float c = dot(o, o) - s.w * s.w;

    float d = b * b - 4 * a * c;

    if (d < 0) {
        return false;
    }

    float d_sqrt   = sqrt(d);
    float distance = (-b - d_sqrt) / (2 * a);

    if (distance > t_max || distance < EPSILON) {
        float back_face_distance = (-b + d_sqrt) / (2 * a);
        if (back_face_distance > EPSILON && back_face_distance < t_max) {
            back_face = true;
            distance  = back_face_distance;
        } else {
            return false;
        }
    }

    hit.back_face = back_face;
    hit.distance  = distance;
    hit.position  = r.origin + r.direction * hit.distance;
    hit.normal    = (hit.position - s.xyz) / s.w * (hit.back_face ? -1 : 1);

    return true;
}

bool ray_aabb_hit(Ray r, vec4 aabb[2], float t_min, float t_max) {
    float tx1 = (aabb[0].x - r.origin.x) / r.direction.x;
    float tx2 = (aabb[1].x - r.origin.x) / r.direction.x;

    float tmin = min(tx1, tx2);
    float tmax = max(tx1, tx2);

    float ty1 = (aabb[0].y - r.origin.y) / r.direction.y;
    float ty2 = (aabb[1].y - r.origin.y) / r.direction.y;

    tmin = max(tmin, min(ty1, ty2));
    tmax = min(tmax, max(ty1, ty2));

    float tz1 = (aabb[0].z - r.origin.z) / r.direction.z;
    float tz2 = (aabb[1].z - r.origin.z) / r.direction.z;

    tmin = max(tmin, min(tz1, tz2));
    tmax = min(tmax, max(tz1, tz2));

    return tmax >= tmin;
}

// no recursion :(
bool ray_bvh_hit(Ray r, out Hit hit) {
    int count = 0;
    int potential_nodes[64];
    int n_nodes = 1;
    potential_nodes[0] = 0;
    hit.distance = MAX_DISTANCE;

    Hit current_hit;

    while (n_nodes != 0) {
        int current = potential_nodes[n_nodes - 1];
        n_nodes -= 1;
        if (current > 0) {
            if (current < MAX_SPHERES) {
                count += 1;
                Sphere s = u_spheres[current - 1];
                if (ray_sphere_hit(r, s, hit.distance, current_hit)) {
                    hit = current_hit;
                    hit.material_id = current;
                }
            }
        } else {
            current = -current;
            if (ray_aabb_hit(r, u_bvh_aabbs[current], EPSILON, hit.distance)) {
                if (n_nodes + 2 <= potential_nodes.length()) {
                    potential_nodes[n_nodes] = u_bvh_nodes[current][0]; n_nodes += 1;
                    potential_nodes[n_nodes] = u_bvh_nodes[current][1]; n_nodes += 1;
                }
            }
        }
    }

    return hit.distance != MAX_DISTANCE;
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

float reflectance(float cosine, float ri) {
    float r0 = (1 - ri) / (1 + ri);
    r0 = r0 * r0;
    return r0 + (1 - r0) * pow(1 - cosine, 5);
}

void main() {
    Ray r = get_ray(v_uv);
    vec3 accumulated_tint = vec3(1);
    Hit hit;

    for (int depth = 0; depth < MAX_DEPTH; depth += 1) {
        if (ray_bvh_hit(r, hit)) {
            vec4 material[2] = u_materials[hit.material_id];
            if (material[1].w > 0.5) {
                f_color.rgb = (0.5 + 0.5 * dot(-hit.normal, r.direction)) * accumulated_tint * material[1].rgb;
                return;
            } else {
                accumulated_tint *= material[0].rgb;
            }
            if (material[0].w == -0) {
                r.direction = normalize(hit.normal + rand_vec3());
                r.origin    = hit.position + hit.normal * EPSILON;
            } else if (material[0].w < 0) {
                vec3 _normal = hit.normal;
                hit.normal   = normalize(hit.normal + rand_vec3() * material[0].w);

                float ri        = hit.back_face ? 1.5 : 1 / 1.5;
                float cos_theta = min(dot(r.direction, -hit.normal), 1);
                float sin_theta = sqrt(1 - cos_theta * cos_theta);

                if ((ri * sin_theta > 1) || (rand() < reflectance(cos_theta, ri))) {
                    r.direction = normalize(reflect(r.direction, hit.normal));
                    r.origin    = hit.position + _normal * EPSILON;
                } else {
                    r.direction = normalize(refract(r.direction, hit.normal, ri));
                    r.origin    = hit.position - _normal * EPSILON;
                }
            } else {
                vec3 _normal = hit.normal;
                hit.normal   = normalize(hit.normal + rand_vec3() * material[0].w);
                r.direction  = normalize(reflect(r.direction, hit.normal));
                r.origin     = hit.position + _normal * EPSILON;
            }
            if (depth == MAX_DEPTH - 1) {
                accumulated_tint = vec3(0);
            }
        } else  {
            if (depth == MAX_DEPTH - 1) {
                accumulated_tint = vec3(0);
            }
            break;
        }
    }
    f_color.rgb = sample_sky_color(r.direction) * accumulated_tint;
}
