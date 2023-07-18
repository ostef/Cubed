// We use a texture array of 6 textures to store our texture atlas for each side
// of the blocks atlas[BlockFace] is the texture atlas for a given block face

g_block_shader : GLuint;
g_texture_atlas : GLuint;
g_all_texture_atlases : [6]GLuint; // We also have separate textures for each face, so we can display them using ImGui
// Atlas is squared so below are both on X and Y axes
g_texture_atlas_size : s64;
g_atlas_cell_count : s64;

g_block_shader_attribs : struct
{
    position : GLuint;
    block_id : GLuint;
    face : GLuint;
    face_corner : GLuint;
    block_height : GLuint;
};

Atlas_Cell_Size_No_Border :: 16;
Atlas_Cell_Border_Size :: 4;
Atlas_Cell_Size :: Atlas_Cell_Size_No_Border + Atlas_Cell_Border_Size * 2;

Vertex :: struct
{
    position : Vec3f;
    block_height : float;
    face : BlockFace;
    corner : BlockFaceCorner;
    block_id : u8;
}

GL_Block_Shader_Header :: #string GLSL
#version 330 core

const int Atlas_Cell_Size_No_Border = %;
const int Atlas_Cell_Border_Size = %;
const int Atlas_Cell_Size = Atlas_Cell_Size_No_Border + Atlas_Cell_Border_Size * 2;
const int Atlas_Cell_Count = %;

GLSL

GL_Block_Shader_Vertex :: #string GLSL
layout (location = 0) in vec3 a_Position;
layout (location = 1) in int a_Block_Id;
layout (location = 2) in int a_Face;
layout (location = 3) in int a_Face_Corner;
layout (location = 4) in float a_Block_Height;

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
centroid out vec3 Tex_Coords;

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

    switch (a_Face_Corner)
    {
    case Block_Corner_Top_Left:
        if (is_side_face)
            atlas_tex_y += int ((1 - a_Block_Height) * Atlas_Cell_Size_No_Border);
        break;
    case Block_Corner_Top_Right:
        if (is_side_face)
            atlas_tex_y += int ((1 - a_Block_Height) * Atlas_Cell_Size_No_Border);
        atlas_tex_x += Atlas_Cell_Size_No_Border;
        break;
    case Block_Corner_Bottom_Left:  atlas_tex_y += Atlas_Cell_Size_No_Border; break;
    case Block_Corner_Bottom_Right: atlas_tex_x += Atlas_Cell_Size_No_Border; atlas_tex_y += Atlas_Cell_Size_No_Border; break;
    }

    ivec3 atlas_size = textureSize (u_Texture_Atlases, 0);
    Tex_Coords.x = float (atlas_tex_x) / float (atlas_size.x);
    Tex_Coords.y = float (atlas_tex_y) / float (atlas_size.y);
    Tex_Coords.z = a_Face;
}
GLSL

GL_Block_Shader_Fragment :: #string GLSL
in vec3 Normal;
centroid in vec3 Tex_Coords;

out vec4 Frag_Color;

uniform sampler2DArray u_Texture_Atlases;

void main ()
{
    vec3 light_direction = normalize (vec3 (0.5, 1, 0.2));
    vec4 sampled = texture (u_Texture_Atlases, Tex_Coords);
    // vec4 sampled = textureLod (u_Texture_Atlas, Tex_Coords, 1);
    Frag_Color.rgb = sampled.rgb * max (dot (Normal, light_direction), 0.25);
    Frag_Color.a = sampled.a;
}
GLSL

DrawInit :: (textures_directory : string) -> bool
{
    if !LoadTextureAtlases (textures_directory)
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

    g_block_shader_attribs.position = xx glGetAttribLocation (g_block_shader, "a_Position");
    g_block_shader_attribs.block_id = xx glGetAttribLocation (g_block_shader, "a_Block_Id");
    g_block_shader_attribs.face = xx glGetAttribLocation (g_block_shader, "a_Face");
    g_block_shader_attribs.face_corner = xx glGetAttribLocation (g_block_shader, "a_Face_Corner");
    g_block_shader_attribs.block_height = xx glGetAttribLocation (g_block_shader, "a_Block_Height");

    return true;
}

// RGBA format
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

ImageBlit :: (dest : *Image, src : Image, dest_x : int, dest_y : int, border : int)
{
    dest_x += border;
    dest_y += border;

    for y : -border..src.height + border - 1
    {
        for x : -border..src.width + border - 1
        {
            sample_x := Clamp (x, 0, src.width - 1);
            sample_y := Clamp (y, 0, src.height - 1);

            pixel := ImageGetPixel (src, sample_x, sample_y);
            ImageSetPixel (dest, dest_x + x, dest_y + y, pixel);
        }
    }
}

LoadTextureAtlases :: (textures_dirname : string) -> bool
{
    #import "stb_image";

    TryLoadTexture :: inline (img : *Image, filename : *u8) -> bool #must
    {
        w, h : s32;
        img.data = cast (*u32) stbi_load (filename, *w, *h, null, 4);
        if !img.data
            return false;

        img.width = w;
        img.height = h;

        return true;
    }

    Texture_Names :: string.[
        "water",
        "stone",
        "bedrock",
        "dirt",
        "grass_block",
        "sand",
        "gravel",
        "red_sand",
        "snow",
        "grass_block_snow",
    ];

    g_atlas_cell_count = cast (int) Ceil (Sqrt (Texture_Names.count + 1));
    g_texture_atlas_size = Atlas_Cell_Size * g_atlas_cell_count;

    textures : [6][Texture_Names.count]Image;
    defer for face : 0..5
    {
        for * textures[face]
        {
            stbi_image_free (xx it.data);
            it.data = null;
        }
    }

    for face : 0..5
    {
        for * textures[face]
        {
            w, h : s32;
            filename : *u8;
            face_name : string;
            second_face_name : string;
            if #complete cast (BlockFace) face ==
            {
            case .East;
                face_name = "east";
                second_face_name = "side";
            case .West;
                face_name = "west";
                second_face_name = "side";
            case .Above;
                face_name = "top";
                second_face_name = "";
            case .Below;
                face_name = "bottom";
                second_face_name = "";
            case .North;
                face_name = "north";
                second_face_name = "side";
            case .South;
                face_name = "south";
                second_face_name = "side";
            }

            filename = FormatToCString (Temp, "%/%_%.png", textures_dirname, Texture_Names[it_index], face_name);
            if !TryLoadTexture (it, filename)
            {
                filename = FormatToCString (Temp, "%/%_%.png", textures_dirname, Texture_Names[it_index], second_face_name);
                if !TryLoadTexture (it, filename)
                {
                    filename = FormatToCString (Temp, "%/%.png", textures_dirname, Texture_Names[it_index]);
                    if !TryLoadTexture (it, filename)
                    {
                        LogError ("Could not load texture % for side %", Texture_Names[it_index], face_name);
                        return false;
                    }
                }
            }

            if it.width != Atlas_Cell_Size_No_Border || it.height != Atlas_Cell_Size_No_Border
            {
                LogError ("Invalid texture dimensions for %: all textures must be % by % pixels",
                    Texture_Names[it_index], Atlas_Cell_Size_No_Border, Atlas_Cell_Size_No_Border);
                return false;
            }
        }
    }

    GL_Utils.StateBlock (GL_TEXTURE_BINDING_2D_ARRAY, (prev : GLuint) {glBindTexture (GL_TEXTURE_2D_ARRAY, prev);});
    GL_Utils.StateBlock (GL_TEXTURE_BINDING_2D, (prev : GLuint) {glBindTexture (GL_TEXTURE_2D, prev);});

    glGenTextures (1, *g_texture_atlas);
    glBindTexture (GL_TEXTURE_2D_ARRAY, g_texture_atlas);

    glTexStorage3D (GL_TEXTURE_2D_ARRAY, Atlas_Cell_Border_Size, GL_RGBA8, xx g_texture_atlas_size, xx g_texture_atlas_size, 6);

    glTexParameteri (GL_TEXTURE_2D_ARRAY, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
    glTexParameteri (GL_TEXTURE_2D_ARRAY, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri (GL_TEXTURE_2D_ARRAY, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri (GL_TEXTURE_2D_ARRAY, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

    glGenTextures (6, g_all_texture_atlases.data);

    atlas : Image;
    atlas.width = xx g_texture_atlas_size;
    atlas.height = xx g_texture_atlas_size;
    atlas.data = Alloc (u32, g_texture_atlas_size * g_texture_atlas_size);
    defer Free (atlas.data);


    for face : 0..5
    {
        memset (atlas.data, 0, g_texture_atlas_size * g_texture_atlas_size * size_of (u32));

        for textures[face]
        {
            block_id := it_index + 1;
            cell_x := block_id % g_atlas_cell_count;
            cell_y := block_id / g_atlas_cell_count;
            tex_x := cell_x * Atlas_Cell_Size;
            tex_y := cell_y * Atlas_Cell_Size;

            ImageBlit (*atlas, it, tex_x, tex_y, Atlas_Cell_Border_Size);
        }

        // glTexImage3D (GL_TEXTURE_2D_ARRAY, 0, GL_RGBA, xx atlas.width, xx atlas.height, xx face, 0, GL_RGBA, GL_UNSIGNED_BYTE, atlas.data);
        glTexSubImage3D (GL_TEXTURE_2D_ARRAY, 0, 0, 0, xx face, xx atlas.width, xx atlas.height, 1, GL_RGBA, GL_UNSIGNED_BYTE, atlas.data);

        glBindTexture (GL_TEXTURE_2D, g_all_texture_atlases[face]);

        glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
        glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

        glTexImage2D (GL_TEXTURE_2D, 0, GL_RGBA, xx atlas.width, xx atlas.height, 0, GL_RGBA, GL_UNSIGNED_BYTE, atlas.data);

        glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_BASE_LEVEL, 0);
        glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_MAX_LEVEL, Atlas_Cell_Border_Size - 1);
        glGenerateMipmap (GL_TEXTURE_2D);
    }

    // It seems auto generating the mipmaps is fine for up to a certain level with a certain border size,
    // so we do that for now. We may manually generate them in the future if it turns out to not work fine.
    glTexParameteri (GL_TEXTURE_2D_ARRAY, GL_TEXTURE_BASE_LEVEL, 0);
    glTexParameteri (GL_TEXTURE_2D_ARRAY, GL_TEXTURE_MAX_LEVEL, Atlas_Cell_Border_Size - 1);
    glGenerateMipmap (GL_TEXTURE_2D_ARRAY);

    LogContentMessage ("Loaded texture atlas: % cells, % by % pixels", g_atlas_cell_count, g_texture_atlas_size, g_texture_atlas_size);

    return true;
}

DrawChunkMesh :: inline (chunk : Chunk, camera : Camera, mesh_type : ChunkMeshType)
{
    if chunk.vertex_counts[mesh_type] == 0
        return;

    GL_Utils.StateBlock (GL_VERTEX_ARRAY_BINDING, (prev : GLuint) {glBindVertexArray (prev);});
    GL_Utils.StateBlock (GL_ARRAY_BUFFER_BINDING, (prev : GLuint) {glBindBuffer (GL_ARRAY_BUFFER, prev);});

    glBindVertexArray (chunk.vaos[mesh_type]);
    glBindBuffer (GL_ARRAY_BUFFER, chunk.vbos[mesh_type]);

    glDrawArrays (GL_TRIANGLES, 0, xx chunk.vertex_counts[mesh_type]);
}

cam : Camera;

DrawCameraFrustum :: (using camera : Camera, using frustum : Frustum)
{
    w, h : s32;
    SDL_GetWindowSize (g_window, *w, *h);

    aspect_ratio := cast (float) w / cast (float) h;

    near_size : Vec2f = ---;
    near_size.x = z_near * Tan (ToRadians (fov_in_degrees * 0.5));
    near_size.y = near_size.x * aspect_ratio;

    far_size : Vec2f = ---;
    far_size.x = z_far * Tan (ToRadians (fov_in_degrees * 0.5));
    far_size.y = far_size.x * aspect_ratio;

    Im3d.DrawQuad (near_plane.normal * near_plane.distance, near_plane.normal, near_size);
    Im3d.DrawArrow (near_plane.normal * near_plane.distance, near_plane.normal * near_plane.distance + near_plane.normal);

    Im3d.DrawQuad (far_plane.normal * far_plane.distance, far_plane.normal, far_size);
    Im3d.DrawArrow (far_plane.normal * far_plane.distance, far_plane.normal * far_plane.distance + far_plane.normal);
}

DrawWorld :: (world : *World, camera : Camera)
{
    // if Im3d.Gizmo ("Cam", cast (*[16]float) *cam.transform_matrix.n)
    // {
    //     cam.position = TranslationVector (cam.transform_matrix);
    //     cam.rotation = QuatfFromMatrix (cam.transform_matrix);
    //     cam.euler_angles = EulerAnglesFromQuat (cam.rotation);
    // }

    view_frustum := MakeViewFrustum (camera);

    // DrawCameraFrustum (cam, view_frustum);

    chunks_to_draw : [..]*Chunk;
    chunks_to_draw.allocator = Temp;

    sqrd_render_distance := cast (float) (g_settings.render_distance * Chunk_Size);
    sqrd_render_distance *= sqrd_render_distance;
    for world.all_loaded_chunks
    {
        camera_horizontal_pos := Vec2f.{camera.position.x, camera.position.z};
        world_chunk_pos := Vec2f.{xx (it.x * Chunk_Size), xx (it.z * Chunk_Size)};

        if SqrdDistance (world_chunk_pos, camera_horizontal_pos) < sqrd_render_distance //&& ChunkIsInFrustum (it, view_frustum)
        {
            ChunkGenerateMeshes (it);
            ArrayPush (*chunks_to_draw, it);
        }

        // if ChunkIsInFrustum (it, view_frustum)
        //     Im3d.DrawAlignedBox (ChunkAABB (it.x, it.z).min, ChunkAABB (it.x, it.z).max);
    }

    // Println ("Drawing % chunks", chunks_to_draw.count);

    GL_Utils.EnableBlock (GL_BLEND);
    GL_Utils.BlendFuncStateBlock ();
    GL_Utils.EnableBlock (GL_DEPTH_TEST);
    GL_Utils.EnableBlock (GL_CULL_FACE);
    GL_Utils.StateBlock (GL_ACTIVE_TEXTURE, (prev : GLenum) {glActiveTexture (prev);});
    GL_Utils.StateBlock (GL_TEXTURE_BINDING_2D_ARRAY, (prev : GLuint) {glBindTexture (GL_TEXTURE_2D_ARRAY, prev);});
    GL_Utils.StateBlock (GL_CURRENT_PROGRAM, (prev : GLuint) {glUseProgram (prev);});

    glBlendFunc (GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    glFrontFace (GL_CW);

    glActiveTexture (0);
    glBindTexture (GL_TEXTURE_2D_ARRAY, g_texture_atlas);
    glUseProgram (g_block_shader);

    loc := glGetUniformLocation (g_block_shader, "u_View_Projection_Matrix");
    glUniformMatrix4fv (loc, 1, GL_TRUE, *camera.view_projection_matrix.r0c0);

    for mesh_type : 0..ChunkMeshType.Count - 1
    {
        for chunks_to_draw
            DrawChunkMesh (it, camera, xx mesh_type);
    }
}
