#version 330 core

#include "common.glsl"

#type_vertex

layout (location = 0) in vec2 a_Position;
layout (location = 1) in vec2 a_Tex_Coords;

out vec3 Frag_Direction;
out vec3 Sun_Direction;

uniform float u_Day_Night_Time;
uniform mat4 u_World_View;
uniform mat4 u_World_Projection;
uniform mat4 u_View_Projection_Matrix;  // This is a 2d orthographic matrix, since we're rendering the sky on a 2d quad the size of the screen

void main ()
{
    gl_Position = u_View_Projection_Matrix * vec4 (a_Position, 0, 1);

    Frag_Direction = inverse (mat3 (u_World_View)) * (inverse (u_World_Projection) * gl_Position).xyz;
    Sun_Direction = vec3 (0, sin (u_Day_Night_Time * 2 * Pi), cos (u_Day_Night_Time * 2 * Pi));
}

#type_fragment

in vec3 Frag_Direction;
in vec3 Sun_Direction;
out vec4 Frag_Color;

uniform sampler2D u_Texture;
uniform vec2 u_Viewport_Size;
uniform float u_Day_Night_Time;

const vec3 Sun_Color = vec3 (1.0, 0.6, 0.05);
const vec3 Sunset_Color = vec3 (1.0, 0.3, 0.0);
const vec3 Day_Sky_Color = vec3 (0.3, 0.4, 0.8);
const vec3 Night_Sky_Color = vec3 (0, 0.004, 0.05);

vec3 ComputeSkyColor (vec3 sun_dir, vec3 view_dir)
{
    const float Atmosphere_Pow = 10.0;  // Increase to make day sky color more present
    const float Scatter_Pow = 1 / 4.0; // Decrease divisor to make the sunset color last longer

    float sun_y = asin (sun_dir.y) / (Pi * 0.5);
    float view_y = asin (view_dir.y) / (Pi * 0.5);

    float atmosphere = sqrt (pow (1.0 - view_y, Atmosphere_Pow));
    float scatter = pow (sun_y, Scatter_Pow);
    scatter = 1.0 - clamp (scatter, 0.0, 1.0);

    const vec3 Unscattered_Color = vec3 (
        pow (Day_Sky_Color.r, 1 / 2.0),
        pow (Day_Sky_Color.g, 1 / 2.0),
        pow (Day_Sky_Color.b, 1 / 2.0)
    );

    vec3 scatter_color = mix (Unscattered_Color, Sunset_Color * 1.5, scatter);

    atmosphere = clamp (atmosphere / 1.3, 0.0, 1.0);

    return mix (Day_Sky_Color, scatter_color, atmosphere);
}

vec3 ComputeSunColor (vec3 sun_dir, vec3 view_dir)
{
    float horizon_attenuation = asin (view_dir.y) / (Pi * 0.5);
    horizon_attenuation *= 4.0;
    horizon_attenuation = clamp (horizon_attenuation, 0.0, 1.0);

    float sun = dot (sun_dir, view_dir);
    float glow = sun;

    sun = clamp (sun, 0.0, 1.0);
    sun = pow (sun, 1000.0);
    sun *= 10.0;
    sun = clamp (sun, 0.0, 1.0);

    glow = pow (glow, 60.0) * 0.5;
    glow = pow (glow, horizon_attenuation);
    glow = clamp (glow, 0.0, 1.0);

    sun *= pow (horizon_attenuation * horizon_attenuation, 1.0 / 1.65);
    glow *= pow (horizon_attenuation * horizon_attenuation, 1.0 / 2.0);

    sun += glow;

    return Sun_Color * sun;
}

void main ()
{
    vec3 dir = normalize (Frag_Direction);
    vec3 sun = normalize (Sun_Direction);
    vec2 dir_uv = CartesianToSphericalUV (dir);
    vec2 sun_uv = CartesianToSphericalUV (sun);

    Frag_Color.rgb = ComputeSkyColor (sun, dir) + ComputeSunColor (sun, dir);
    Frag_Color.a = 1.0;
}
