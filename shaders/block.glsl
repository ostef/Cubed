#version 330 core

#program_import "Block_Definitions"

#include "common.glsl"

#type_vertex

layout (location = 0) in vec3 a_Position;
layout (location = 1) in int a_Block_Id;
layout (location = 2) in int a_Face;
layout (location = 3) in int a_Face_Corner;
layout (location = 4) in float a_Block_Height;
layout (location = 5) in float a_Temperature;
layout (location = 6) in float a_Humidity;

flat out int Block_ID;
flat out int Block_Face;
out vec3 Normal;
centroid out vec3 Atlas_Tex_Coords;
centroid out vec2 Block_Tex_Coords;
out vec3 Grass_Color;

uniform mat4 u_View_Projection_Matrix;
uniform sampler2DArray u_Texture_Atlases;

void main ()
{
    gl_Position = u_View_Projection_Matrix * vec4 (a_Position, 1);

    switch (a_Face)
    {
    case Block_Face_East:  Normal = vec3 ( 1, 0, 0); break;
    case Block_Face_West:  Normal = vec3 (-1, 0, 0); break;
    case Block_Face_Above: Normal = vec3 (0,  1, 0); break;
    case Block_Face_Below: Normal = vec3 (0, -1, 0); break;
    case Block_Face_North: Normal = vec3 (0, 0,  1); break;
    case Block_Face_South: Normal = vec3 (0, 0, -1); break;
    }

    int atlas_cell_x = a_Block_Id % Atlas_Cell_Count;
    int atlas_cell_y = a_Block_Id / Atlas_Cell_Count;
    int atlas_tex_x = atlas_cell_x * Atlas_Cell_Size + Atlas_Cell_Border_Size;
    int atlas_tex_y = atlas_cell_y * Atlas_Cell_Size + Atlas_Cell_Border_Size;

    bool is_side_face = a_Face != Block_Face_Above && a_Face != Block_Face_Below;

    Grass_Color = BilinearMix (Grass_Color_00, Grass_Color_10, Grass_Color_01, Grass_Color_11, a_Temperature, a_Humidity);

    Block_Tex_Coords = vec2 (0, 0);
    switch (a_Face_Corner)
    {
    case Block_Corner_Top_Left:
        if (is_side_face)
        {
            atlas_tex_y += int ((1 - a_Block_Height) * Atlas_Cell_Size_No_Border);
            Block_Tex_Coords.y = 1 - a_Block_Height;
        }
        break;

    case Block_Corner_Top_Right:
        if (is_side_face)
        {
            atlas_tex_y += int ((1 - a_Block_Height) * Atlas_Cell_Size_No_Border);
            Block_Tex_Coords.y = 1 - a_Block_Height;
        }
        Block_Tex_Coords.x = 1;
        atlas_tex_x += Atlas_Cell_Size_No_Border;
        break;

    case Block_Corner_Bottom_Left:
        atlas_tex_y += Atlas_Cell_Size_No_Border;
        Block_Tex_Coords.y = 1;
        break;

    case Block_Corner_Bottom_Right:
        Block_Tex_Coords.x = 1;
        Block_Tex_Coords.y = 1;
        atlas_tex_x += Atlas_Cell_Size_No_Border;
        atlas_tex_y += Atlas_Cell_Size_No_Border;
        break;
    }

    ivec3 atlas_size = textureSize (u_Texture_Atlases, 0);
    Atlas_Tex_Coords.x = float (atlas_tex_x) / float (atlas_size.x);
    Atlas_Tex_Coords.y = float (atlas_tex_y) / float (atlas_size.y);
    Atlas_Tex_Coords.z = a_Face;

    Block_ID = a_Block_Id;
    Block_Face = a_Face;
}

#type_fragment

flat in int Block_ID;
flat in int Block_Face;
in vec3 Normal;
centroid in vec3 Atlas_Tex_Coords;
centroid in vec2 Block_Tex_Coords;
in vec3 Grass_Color;

out vec4 Frag_Color;

uniform sampler2DArray u_Texture_Atlases;
uniform sampler2D u_Grass_Overlay;

void main ()
{
    vec3 light_direction = normalize (vec3 (0.5, 1, 0.2));
    vec4 sampled = texture (u_Texture_Atlases, Atlas_Tex_Coords);

    Frag_Color = sampled;
    if (Block_ID == Block_Grass && Block_Face == Block_Face_Above)
        Frag_Color.rgb *= Grass_Color;

    if (Block_ID == Block_Grass && Block_Face != Block_Face_Above && Block_Face != Block_Face_Below)
    {
        vec4 grass_overlay_sample = texture (u_Grass_Overlay, Block_Tex_Coords);
        grass_overlay_sample.rgb *= Grass_Color;
        Frag_Color = mix (Frag_Color, grass_overlay_sample, grass_overlay_sample.a);
    }

    Frag_Color.rgb *= max (dot (Normal, light_direction), 0.25);
}
