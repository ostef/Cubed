#version 330 core

#program_import "Block_Definitions"

#type_vertex

layout (location = 0) in vec3 a_Position;
layout (location = 1) in vec3 a_Normal;
layout (location = 2) in vec2 a_Tex_Coords;
layout (location = 3) in int a_Block_Id;
layout (location = 4) in float a_Temperature;
layout (location = 5) in float a_Humidity;

flat out int Block_ID;
out vec3 Normal;
centroid out vec2 Atlas_Tex_Coords;
centroid out vec2 Block_Tex_Coords;
out vec3 Grass_Color;

uniform mat4 u_View_Projection_Matrix;
uniform sampler2DArray u_Texture_Atlases;

vec3 BilinearMix (vec3 a, vec3 b, vec3 c, vec3 d, float s, float t)
{
    vec3 x = mix (a, b, s);
    vec3 y = mix (c, d, s);

    return mix (x, y, t);
}

void main ()
{
    gl_Position = u_View_Projection_Matrix * vec4 (a_Position, 1);

    int atlas_cell_x = a_Block_Id % Atlas_Cell_Count;
    int atlas_cell_y = a_Block_Id / Atlas_Cell_Count;
    int atlas_tex_x = atlas_cell_x * Atlas_Cell_Size + Atlas_Cell_Border_Size;
    int atlas_tex_y = atlas_cell_y * Atlas_Cell_Size + Atlas_Cell_Border_Size;

    Grass_Color = BilinearMix (Grass_Color_00, Grass_Color_10, Grass_Color_01, Grass_Color_11, a_Temperature, a_Humidity);

    Block_Tex_Coords = a_Tex_Coords;
    Block_Tex_Coords.y = 1 - Block_Tex_Coords.y;

    ivec3 atlas_size = textureSize (u_Texture_Atlases, 0);
    Atlas_Tex_Coords.x = (Block_Tex_Coords.x * Atlas_Cell_Size_No_Border + atlas_tex_x) / float (atlas_size.x);
    Atlas_Tex_Coords.y = (Block_Tex_Coords.y * Atlas_Cell_Size_No_Border + atlas_tex_y) / float (atlas_size.y);

    Block_ID = a_Block_Id;
    Normal = a_Normal;
}

#type_fragment

flat in int Block_ID;
in vec3 Normal;
centroid in vec2 Atlas_Tex_Coords;
centroid in vec2 Block_Tex_Coords;
in vec3 Grass_Color;

out vec4 Frag_Color;

uniform sampler2DArray u_Texture_Atlases;

void main ()
{
    vec4 sampled = texture (u_Texture_Atlases, vec3(Atlas_Tex_Coords, 0));
    if (sampled.a < 1)
        discard;

    Frag_Color.rgb = sampled.rgb;
    if (Block_ID == Block_Grass_Foliage)
        Frag_Color.rgb *= Grass_Color;

    Frag_Color.a = 1;
}
