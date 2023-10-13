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
uniform mat4 u_View_Projection_Matrix;

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

const float Br = 0.0005;
const float Bm = 0.0003;
const float g =  0.9200;
const vec3 nitrogen = vec3(0.650, 0.570, 0.475);
const vec3 Kr = Br / pow(nitrogen, vec3(4.0));
const vec3 Km = Bm / pow(nitrogen, vec3(0.84));

void main ()
{
    vec3 dir = normalize (Frag_Direction);
    vec3 sun = normalize (Sun_Direction);

    /*
    if (dir.y < 0)
        discard;

    // Atmospheric scattering
    float mu = dot (dir, sun);
    float rayleigh = 3.0 / (8.0 * 3.14) * (1.0 + mu * mu);
    vec3 mie = (Kr + Km * (1.0 - g * g) / (2.0 + g * g) / pow (1.0 + g * g - 2.0 * g * mu, 1.5)) / (Br + Bm);

    vec3 day_extinction = exp (-exp (-((dir.y + sun.y * 4.0) * (exp (-dir.y * 16.0) + 0.1) / 80.0) / Br)
        * (exp (-dir.y * 16.0) + 0.1) * Kr / Br) * exp (-dir.y * exp (-dir.y * 8.0) * 4.0) * exp (-dir.y * 2.0) * 4.0;
    vec3 night_extinction = vec3 (1.0 - exp (sun.y)) * 0.2;
    vec3 extinction = mix (day_extinction, night_extinction, -sun.y * 0.2 + 0.5);

    Frag_Color.rgb = rayleigh * mie * extinction;
    */

    vec2 uv = CartesianToSphericalUV (dir);

    Frag_Color.rgb = texture (u_Texture, uv).rgb;

    Frag_Color.a = 1.0;
}
