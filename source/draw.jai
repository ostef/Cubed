g_block_shader : GLuint;
g_texture_atlas : GLuint;
// Atlas is squared so below are both on X and Y axes
g_texture_atlas_size : s64;
g_atlas_cell_count : s64;

Atlas_Cell_Size_No_Border :: 16;
Atlas_Cell_Border_Size :: 4;
Atlas_Cell_Size :: Atlas_Cell_Size_No_Border + Atlas_Cell_Border_Size * 2;

GL_Block_Shader_Header :: #string GLSL
#version 330 core

const int Atlas_Cell_Size_No_Border = %;
const int Atlas_Cell_Border_Size = %;
const int Atlas_Cell_Size = Atlas_Cell_Size_No_Border + Atlas_Cell_Border_Size * 2;
const int Atlas_Cell_Count = %;

GLSL

GL_Block_Shader_Vertex :: #string GLSL
layout (location = 0) in vec3 a_Position;
layout (location = 1) in int a_Face;
layout (location = 2) in int a_Block_Id;
layout (location = 3) in int a_Face_Corner;

const int Block_Face_East  = 0; // +X
const int Block_Face_West  = 1; // -X
const int Block_Face_Above = 2; // +Y
const int Block_Face_Below = 3; // -Y
const int Block_Face_North = 4; // +Z
const int Block_Face_South = 5; // -Z

const int Block_Corner_Top_Left     = 0;
const int Block_Corner_Top_Right    = 1;
const int Block_Corner_Bottom_Left  = 2;
const int Block_Corner_Bottom_Right = 3;

out vec3 Normal;
centroid out vec2 Tex_Coords;

uniform mat4 u_View_Projection_Matrix;
uniform sampler2D u_Texture_Atlas;

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

    switch (a_Face_Corner)
    {
    case Block_Corner_Top_Left:     break;
    case Block_Corner_Top_Right:    atlas_tex_x += Atlas_Cell_Size_No_Border; break;
    case Block_Corner_Bottom_Left:  atlas_tex_y += Atlas_Cell_Size_No_Border; break;
    case Block_Corner_Bottom_Right: atlas_tex_x += Atlas_Cell_Size_No_Border; atlas_tex_y += Atlas_Cell_Size_No_Border; break;
    }

    ivec2 atlas_size = textureSize (u_Texture_Atlas, 0);
    Tex_Coords.x = float (atlas_tex_x) / float (atlas_size.x);
    Tex_Coords.y = float (atlas_tex_y) / float (atlas_size.y);
}
GLSL

GL_Block_Shader_Fragment :: #string GLSL
in vec3 Normal;
centroid in vec2 Tex_Coords;

out vec4 Frag_Color;

uniform sampler2D u_Texture_Atlas;

void main ()
{
    vec3 light_direction = normalize (vec3 (0.5, 1, 0.2));
    vec4 sampled = texture (u_Texture_Atlas, Tex_Coords);
    // vec4 sampled = textureLod (u_Texture_Atlas, Tex_Coords, 1);
    Frag_Color.rgb = sampled.rgb * max (dot (Normal, light_direction), 0.25);
    Frag_Color.a = sampled.a;
}
GLSL

DrawInit :: (textures_directory : string) -> bool
{
    if !LoadTextureAtlas (textures_directory)
    {
        LogError ("Could not load textures at %", textures_directory);
        return false;
    }

    shader_header := FormatString (GL_Block_Shader_Header, Atlas_Cell_Size_No_Border, Atlas_Cell_Border_Size, g_atlas_cell_count);
    vertex_source   := StringJoin (shader_header, GL_Block_Shader_Vertex);
    fragment_source := StringJoin (shader_header, GL_Block_Shader_Fragment);
    g_block_shader = GL_Utils.CreateShaderProgram (vertex_source, fragment_source);
    if !g_block_shader
        return false;

    return true;
}

Image :: struct
{
    width, height : s32;
    data : *u32;
}

ImageGetPixel :: inline (img : Image, x : int, y : int) -> u32 #must
{
    Assert (x >= 0 && x < img.width, "Texture x index out of bounds (got %, expected [0;%])", x, img.width - 1);
    Assert (y >= 0 && y < img.height, "Texture y index out of bounds (got %, expected [0;%])", y, img.height - 1);

    return img.data[y * img.width + x];
}

ImageSetPixel :: inline (img : *Image, x : int, y : int, pixel : u32)
{
    Assert (x >= 0 && x < img.width, "Texture x index out of bounds (got %, expected [0;%])", x, img.width - 1);
    Assert (y >= 0 && y < img.height, "Texture y index out of bounds (got %, expected [0;%])", y, img.height - 1);

    img.data[y * img.width + x] = pixel;
}

ImageBlit :: (dest : *Image, src : Image, dest_x : int, dest_y : int)
{
    dest_x += Atlas_Cell_Border_Size;
    dest_y += Atlas_Cell_Border_Size;

    for y : -Atlas_Cell_Border_Size..Atlas_Cell_Size_No_Border + Atlas_Cell_Border_Size - 1
    {
        for x : -Atlas_Cell_Border_Size..Atlas_Cell_Size_No_Border + Atlas_Cell_Border_Size - 1
        {
            sample_x := Clamp (x, 0, src.width - 1);
            sample_y := Clamp (y, 0, src.height - 1);

            pixel := ImageGetPixel (src, sample_x, sample_y);
            ImageSetPixel (dest, dest_x + x, dest_y + y, pixel);
        }
    }
}

LoadTextureAtlas :: (textures_dirname : string) -> bool
{
    #import "stb_image";

    Texture_Names :: string.[
        "dirt.png",
        "stone.png",
        "bedrock.png",
        "water.png",
        "five.png",
        "six.png",
        "seven.png",
        "eight.png",
    ];

    g_atlas_cell_count = cast (int) Ceil (Sqrt (Texture_Names.count + 1));
    g_texture_atlas_size = Atlas_Cell_Size * g_atlas_cell_count;

    atlas_data := Alloc (u32, g_texture_atlas_size * g_texture_atlas_size);
    defer Free (atlas_data);

    textures : [Texture_Names.count]Image;
    defer for i : 0..Texture_Names.count - 1
        stbi_image_free (xx textures[i].data);

    GL_Utils.StateBlock (GL_TEXTURE_BINDING_2D, (prev : GLuint) {glBindTexture (GL_TEXTURE_2D, prev);});

    glGenTextures (1, *g_texture_atlas);
    glBindTexture (GL_TEXTURE_2D, g_texture_atlas);

    glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
    glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_BASE_LEVEL, 0);
    glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_MAX_LEVEL, Atlas_Cell_Border_Size - 1);

    for * textures
    {
        w, h : s32;
        filename := FormatToCString (Temp, "%/%", textures_dirname, Texture_Names[it_index]);
        it.data = cast (*u32) stbi_load (filename, *w, *h, null, 4);
        if !it.data
        {
            LogError ("Could not load texture %", Texture_Names[it_index]);
            return false;
        }

        it.width = w;
        it.height = h;

        if w != Atlas_Cell_Size_No_Border || h != Atlas_Cell_Size_No_Border
        {
            LogError ("Invalid texture dimensions for %: all textures must be % by % pixels",
                Texture_Names[it_index], Atlas_Cell_Size_No_Border, Atlas_Cell_Size_No_Border);
            return false;
        }
    }

    atlas : Image;
    atlas.width = xx g_texture_atlas_size;
    atlas.height = xx g_texture_atlas_size;
    atlas.data = atlas_data;
    memset (atlas.data, 0, atlas.width * atlas.height * size_of (u32));
    for textures
    {
        block_id := it_index + 1;
        cell_x := block_id % g_atlas_cell_count;
        cell_y := block_id / g_atlas_cell_count;
        tex_x := cell_x * Atlas_Cell_Size;
        tex_y := cell_y * Atlas_Cell_Size;

        ImageBlit (*atlas, it, tex_x, tex_y);
    }

    glTexImage2D (GL_TEXTURE_2D, 0, GL_RGBA, xx atlas.width, xx atlas.height, 0, GL_RGBA, GL_UNSIGNED_BYTE, atlas.data);

    // It seems auto generating the mipmaps is fine for up to a certain level with a certain border size,
    // so we do that for now. We may manually generate them in the future if it turns out to not work fine.
    glGenerateMipmap (GL_TEXTURE_2D);

    LogContentMessage ("Loaded texture atlas: % cells, % by % pixels", g_atlas_cell_count, g_texture_atlas_size, g_texture_atlas_size);

    return true;
}

DrawChunkMesh :: inline (chunk : *Chunk, camera : *Camera, mesh_type : ChunkMeshType)
{
    if chunk.vertex_counts[mesh_type] == 0
        return;

    GL_Utils.StateBlock (GL_VERTEX_ARRAY_BINDING, (prev : GLuint) {glBindVertexArray (prev);});
    GL_Utils.StateBlock (GL_ARRAY_BUFFER_BINDING, (prev : GLuint) {glBindBuffer (GL_ARRAY_BUFFER, prev);});

    glBindVertexArray (chunk.vaos[mesh_type]);
    glBindBuffer (GL_ARRAY_BUFFER, chunk.vbos[mesh_type]);

    glDrawArrays (GL_TRIANGLES, 0, xx chunk.vertex_counts[mesh_type]);
}

DrawWorld :: (world : *World, camera : *Camera)
{
    chunks_to_draw : [..]*Chunk;
    chunks_to_draw.allocator = Temp;

    for world.all_loaded_chunks
    {
        camera_horizontal_pos := Vec2f.{camera.position.x, camera.position.z};
        world_chunk_pos := Vec2f.{xx (it.x * Chunk_Size), xx (it.z * Chunk_Size)};

        if Distance (world_chunk_pos, camera_horizontal_pos) < xx g_settings.render_distance
        {
            ChunkGenerateMeshes (it);
            ArrayPush (*chunks_to_draw, it);
        }
    }

    GL_Utils.EnableBlock (GL_BLEND);
    GL_Utils.StateBlock (GL_ACTIVE_TEXTURE, (prev : GLenum) {glActiveTexture (prev);});
    GL_Utils.StateBlock (GL_TEXTURE_BINDING_2D, (prev : GLuint) {glBindTexture (GL_TEXTURE_2D, prev);});
    GL_Utils.StateBlock (GL_CURRENT_PROGRAM, (prev : GLuint) {glUseProgram (prev);});
    GL_Utils.BlendFuncStateBlock ();

    glBlendFunc (GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    glActiveTexture (0);
    glBindTexture (GL_TEXTURE_2D, g_texture_atlas);
    glUseProgram (g_block_shader);

    loc := glGetUniformLocation (g_block_shader, "u_View_Projection_Matrix");
    glUniformMatrix4fv (loc, 1, GL_TRUE, *camera.view_projection_matrix.r0c0);

    for mesh_type : 0..ChunkMeshType.Count - 1
    {
        for chunks_to_draw
            DrawChunkMesh (it, camera, xx mesh_type);
    }
}
