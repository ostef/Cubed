#version 330 core

#type_vertex

layout (location = 0) in vec3 a_Position;
layout (location = 1) in vec3 a_Normal;
layout (location = 2) in vec2 a_Tex_Coords;

uniform mat4 u_Model_Matrix;
uniform mat4 u_View_Projection_Matrix;

out vec2 Tex_Coords;
out vec3 Normal;

void main ()
{
    gl_Position = u_View_Projection_Matrix * u_Model_Matrix * vec4 (a_Position, 1);
    Tex_Coords = a_Tex_Coords;
    Tex_Coords.y = 1 - Tex_Coords.y;
    Normal = (u_Model_Matrix * vec4 (a_Normal, 0)).xyz;
}

#type_fragment

uniform sampler2D u_Texture;
uniform bool u_Use_Texture;
uniform vec4 u_Color;

in vec2 Tex_Coords;
in vec3 Normal;

out vec4 Frag_Color;

void main ()
{
    if (u_Use_Texture)
    {
        vec4 color = texture (u_Texture, Tex_Coords);
        Frag_Color = color * u_Color;
    }
    else
    {
        Frag_Color = u_Color;
    }
}
