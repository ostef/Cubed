#version 330 core

#type_vertex

const int Max_Joints = 1000;

layout (location = 0) in vec3 a_Position;
layout (location = 1) in vec3 a_Normal;
layout (location = 2) in vec2 a_Tex_Coords;
layout (location = 3) in int a_Joint_Id;

uniform mat4 u_Model_Matrix;
uniform mat4 u_View_Projection_Matrix;

layout (std140) uniform Skinning_Data
{
    mat4 u_Skinning_Matrices[Max_Joints];
};

out vec2 Tex_Coords;
out vec3 Normal;

void main ()
{
    vec3 model_position = vec3 (0);
    vec3 model_normal = vec3 (0);
    if (a_Joint_Id < 0)
    {
        model_position = a_Position;
        model_normal   = a_Normal;
    }
    else
    {
        mat4 skinning_matrix = u_Skinning_Matrices[a_Joint_Id];
        model_position = (skinning_matrix * vec4 (a_Position, 1)).xyz;
        model_normal = (skinning_matrix * vec4 (a_Normal, 0)).xyz;
    }

    gl_Position = u_View_Projection_Matrix * u_Model_Matrix * vec4 (model_position, 1);
    Tex_Coords = a_Tex_Coords;
    Tex_Coords.y = 1 - Tex_Coords.y;
    Normal = (u_Model_Matrix * vec4 (model_normal, 0)).xyz;
}

#type_fragment

uniform sampler2D u_Texture;

in vec2 Tex_Coords;
in vec3 Normal;

out vec4 Frag_Color;

void main ()
{
    vec4 color = texture (u_Texture, Tex_Coords);
    Frag_Color = color;
}
