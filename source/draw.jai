// We use a texture array of 6 textures to store our texture atlas for each side
// of the blocks. Atlas[BlockFace] is the texture atlas for a given block face

g_block_shader : GLuint;
g_skinned_mesh_shader : GLuint;
g_texture_atlas : GLuint;
g_grass_overlay_texture : GLuint;
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
    temperature : GLuint;
    humidity : GLuint;
};

Atlas_Cell_Size_No_Border :: 16;
Atlas_Cell_Border_Size :: 4;
Atlas_Cell_Size :: Atlas_Cell_Size_No_Border + Atlas_Cell_Border_Size * 2;

Grass_Color_00 := Vec3f.{0.5372, 0.6980, 0.6078};
Grass_Color_10 := Vec3f.{0.7411, 0.7176, 0.3333};
Grass_Color_01 := Vec3f.{0.3333, 0.7764, 0.2509};
Grass_Color_11 := Vec3f.{0.3333, 0.7764, 0.2509};

Vertex :: struct
{
    position : Vec3f;
    block_height : float;
    temperature : float;
    humidity : float;
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

const vec3 Grass_Color_00 = vec3 (%, %, %);
const vec3 Grass_Color_10 = vec3 (%, %, %);
const vec3 Grass_Color_01 = vec3 (%, %, %);
const vec3 Grass_Color_11 = vec3 (%, %, %);

%
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

GLSL

GL_Block_Shader_Vertex :: #string GLSL
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

vec3 BilinearMix (vec3 a, vec3 b, vec3 c, vec3 d, float s, float t)
{
    vec3 x = mix (a, b, s);
    vec3 y = mix (c, d, s);

    return mix (x, y, t);
}

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
GLSL

GL_Block_Shader_Fragment :: #string GLSL
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

    Frag_Color.rgb = sampled.rgb;
    if (Block_ID == Block_Grass && Block_Face == Block_Face_Above)
        Frag_Color.rgb *= Grass_Color;
    Frag_Color.a = sampled.a;

    vec4 grass_overlay_sample = vec4 (0, 0, 0, 0);
    if (Block_ID == Block_Grass && Block_Face != Block_Face_Above && Block_Face != Block_Face_Below)
    {
        grass_overlay_sample = texture (u_Grass_Overlay, Block_Tex_Coords);
        grass_overlay_sample.rgb *= Grass_Color;
        Frag_Color = mix (Frag_Color, grass_overlay_sample, grass_overlay_sample.a);
    }

    Frag_Color.rgb *= max (dot (Normal, light_direction), 0.25);
}
GLSL

GL_Skinned_Mesh_Vertex_Shader :: #string GLSL
#version 330 core

layout (location = 0) in vec3 a_Position;
layout (location = 1) in vec3 a_Normal;
layout (location = 2) in vec2 a_Tex_Coords;
layout (location = 3) in int a_Joint_Id;

uniform mat4 u_Model_Matrix;
uniform mat4 u_View_Projection_Matrix;

out vec2 Tex_Coords;
out vec3 Normal;

void main ()
{
    gl_Position = u_View_Projection_Matrix * u_Model_Matrix * vec4 (a_Position, 1);
    Tex_Coords = a_Tex_Coords;
    Normal = a_Normal;
}
GLSL

GL_Skinned_Mesh_Fragment_Shader :: #string GLSL
#version 330 core

uniform sampler2D u_Texture;

in vec2 Tex_Coords;
in vec3 Normal;

out vec4 Frag_Color;

void main ()
{
    vec4 color = texture (u_Texture, Tex_Coords);
    Frag_Color = vec4 (Normal, 1);
}
GLSL

ReloadShaders :: () -> bool
{
    GetAttribLocation :: inline (shader : GLuint, $name : string, location := #caller_location) -> GLuint, bool
    {
        loc := glGetAttribLocation (shader, name);
        if loc < 0
        {
            LogError ("Shader attribute % does not exist", name, location = location);
            return 0xffffffff, false;
        }

        return xx loc, true;
    }

    {
        block_ids_string : string;
        {
            builder : StringBuilder;
            builder.allocator = Temp;

            for i : 0..BlockID.Count
                StringBuilderAppend (*builder, "const int Block_% = %;\n", i, cast (int) i);

            block_ids_string = StringBuilderBuild (*builder, allocator = Temp);
        }

        shader_header := FormatString (GL_Block_Shader_Header,
            Atlas_Cell_Size_No_Border, Atlas_Cell_Border_Size, g_atlas_cell_count,
            Grass_Color_00.r, Grass_Color_00.g, Grass_Color_00.b,
            Grass_Color_10.r, Grass_Color_10.g, Grass_Color_10.b,
            Grass_Color_01.r, Grass_Color_01.g, Grass_Color_01.b,
            Grass_Color_11.r, Grass_Color_11.g, Grass_Color_11.b,
            block_ids_string
        );

        vertex_source   := StringJoin (shader_header, GL_Block_Shader_Vertex);
        fragment_source := StringJoin (shader_header, GL_Block_Shader_Fragment);

        new_shader := GL_Utils.CreateShaderProgram (vertex_source, fragment_source);
        if !new_shader
            return false;

        attribs : type_of (g_block_shader_attribs);
        ok : bool;

        attribs.position, ok = GetAttribLocation (new_shader, "a_Position");
        if !ok
        {
            glDeleteProgram (new_shader);
            return false;
        }

        attribs.block_id, ok = GetAttribLocation (new_shader, "a_Block_Id");
        if !ok
        {
            glDeleteProgram (new_shader);
            return false;
        }

        attribs.face, ok = GetAttribLocation (new_shader, "a_Face");
        if !ok
        {
            glDeleteProgram (new_shader);
            return false;
        }

        attribs.face_corner, ok = GetAttribLocation (new_shader, "a_Face_Corner");
        if !ok
        {
            glDeleteProgram (new_shader);
            return false;
        }

        attribs.block_height, ok = GetAttribLocation (new_shader, "a_Block_Height");
        if !ok
        {
            glDeleteProgram (new_shader);
            return false;
        }

        attribs.temperature, ok = GetAttribLocation (new_shader, "a_Temperature");
        if !ok
        {
            glDeleteProgram (new_shader);
            return false;
        }

        attribs.humidity, ok = GetAttribLocation (new_shader, "a_Humidity");
        if !ok
        {
            glDeleteProgram (new_shader);
            return false;
        }

        glDeleteProgram (g_block_shader);
        g_block_shader = new_shader;
        g_block_shader_attribs = attribs;
    }

    {
        new_shader := GL_Utils.CreateShaderProgram (GL_Skinned_Mesh_Vertex_Shader, GL_Skinned_Mesh_Fragment_Shader);
        if !new_shader
            return false;

        glDeleteProgram (g_skinned_mesh_shader);
        g_skinned_mesh_shader = new_shader;
    }

    return true;
}

DrawInit :: (textures_directory : string) -> bool
{
    if !LoadTextureAtlases (textures_directory)
    {
        LogError ("Could not load textures at %", textures_directory);
        return false;
    }

    if !ReloadShaders ()
        return false;

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

LoadSingleTexture :: (filename : *u8) -> GLuint #must
{
    w, h : s32;
    data := stbi_load (filename, *w, *h, null, 4);
    if !data
        return 0;

    defer stbi_image_free (data);

    texture : GLuint;
    glGenTextures (1, *texture);
    if !texture
        return 0;

    glBindTexture (GL_TEXTURE_2D, texture);

    glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
    glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

    glTexImage2D (GL_TEXTURE_2D, 0, GL_RGBA, xx w, xx h, 0, GL_RGBA, GL_UNSIGNED_BYTE, data);

    glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_BASE_LEVEL, 0);
    glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_MAX_LEVEL, Atlas_Cell_Border_Size - 1);
    glGenerateMipmap (GL_TEXTURE_2D);

    return texture;
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

    g_grass_overlay_texture = LoadSingleTexture (FormatToCString (Temp, "%/grass_block_side_overlay.png", textures_dirname));
    if !g_grass_overlay_texture
    {
        LogError ("Could not load texture grass_block_side_overlay.png");
        return false;
    }

    LogContentMessage ("Loaded texture atlas: % cells, % by % pixels", g_atlas_cell_count, g_texture_atlas_size, g_texture_atlas_size);

    return true;
}

DrawSkinnedMesh :: inline (mesh : SkinnedMesh, camera : Camera, model_matrix : Mat4f)
{
    GL_Utils.StateBlock (GL_VERTEX_ARRAY_BINDING, (prev : GLuint) {glBindVertexArray (prev);});
    GL_Utils.StateBlock (GL_ARRAY_BUFFER_BINDING, (prev : GLuint) {glBindBuffer (GL_ARRAY_BUFFER, prev);});
    GL_Utils.StateBlock (GL_ELEMENT_ARRAY_BUFFER_BINDING, (prev : GLuint) {glBindBuffer (GL_ELEMENT_ARRAY_BUFFER, prev);});
    GL_Utils.EnableBlock (GL_DEPTH_TEST);
    GL_Utils.EnableBlock (GL_CULL_FACE);
    GL_Utils.StateBlock (GL_ACTIVE_TEXTURE, (prev : GLenum) {glActiveTexture (prev);});
    GL_Utils.StateBlock (GL_TEXTURE_BINDING_2D_ARRAY, (prev : GLuint) {glBindTexture (GL_TEXTURE_2D_ARRAY, prev);});
    GL_Utils.StateBlock (GL_CURRENT_PROGRAM, (prev : GLuint) {glUseProgram (prev);});

    glUseProgram (g_skinned_mesh_shader);

    loc := glGetUniformLocation (g_skinned_mesh_shader, "u_View_Projection_Matrix");
    glUniformMatrix4fv (loc, 1, GL_TRUE, *camera.view_projection_matrix.r0c0);

    loc = glGetUniformLocation (g_skinned_mesh_shader, "u_Model_Matrix");
    glUniformMatrix4fv (loc, 1, GL_TRUE, *model_matrix.r0c0);

    glBindVertexArray (mesh.vao);
    glBindBuffer (GL_ARRAY_BUFFER, mesh.vbo);
    glBindBuffer (GL_ELEMENT_ARRAY_BUFFER, mesh.ibo);

    glDrawElements (GL_TRIANGLES, xx mesh.index_count, GL_UNSIGNED_INT, null);
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

DrawCameraFrustum :: (using camera : Camera)
{
    using frustum := MakeViewFrustum (camera);

    w, h : s32;
    SDL_GetWindowSize (g_window, *w, *h);

    aspect_ratio := cast (float) w / cast (float) h;

    half_near_v_side := z_near * Tan (ToRadians (fov_in_degrees * 0.5));
    half_near_h_side := half_near_v_side * aspect_ratio;
    half_near_h_hypothenuse := Sqrt (z_near * z_near + half_near_h_side * half_near_h_side) * 0.5;
    half_near_v_hypothenuse := Sqrt (z_near * z_near + half_near_v_side * half_near_v_side) * 0.5;

    half_far_v_side := z_far * Tan (ToRadians (fov_in_degrees * 0.5));
    half_far_h_side := half_far_v_side * aspect_ratio;
    half_far_h_hypothenuse := Sqrt (z_far * z_far + half_far_h_side * half_far_h_side) * 0.5;
    half_far_v_hypothenuse := Sqrt (z_far * z_far + half_far_v_side * half_far_v_side) * 0.5;

    Im3d.DrawQuad (near_plane.origin, near_plane.normal, .{ half_near_h_side, half_near_v_side });
    Im3d.DrawArrow (near_plane.origin, near_plane.origin + near_plane.normal);

    Im3d.DrawQuad (far_plane.origin, far_plane.normal, .{ half_far_h_side, half_far_v_side });
    Im3d.DrawArrow (far_plane.origin, far_plane.origin + far_plane.normal);

    Im3d.DrawQuad (left_plane.origin, left_plane.normal, .{ half_far_h_hypothenuse - half_near_h_hypothenuse, half_far_v_side });
    Im3d.DrawArrow (left_plane.origin, left_plane.origin + left_plane.normal);

    Im3d.DrawQuad (right_plane.origin, right_plane.normal, .{ half_far_h_hypothenuse - half_near_h_hypothenuse, half_far_v_side });
    Im3d.DrawArrow (right_plane.origin, right_plane.origin + right_plane.normal);

    Im3d.DrawQuad (top_plane.origin, top_plane.normal, .{ half_far_h_side, half_far_v_hypothenuse - half_near_v_hypothenuse });
    Im3d.DrawArrow (top_plane.origin, top_plane.origin + top_plane.normal);

    Im3d.DrawQuad (bottom_plane.origin, bottom_plane.normal, .{ half_far_h_side, half_far_v_hypothenuse - half_near_v_hypothenuse });
    Im3d.DrawArrow (bottom_plane.origin, bottom_plane.origin + bottom_plane.normal);
}

g_chunks_drawn_this_frame := 0;

DrawWorld :: (world : *World, camera : Camera)
{
    #if false
    {
        current_time := cast (float) Basic.to_float64_seconds (Basic.current_time_monotonic ());

        dummy_camera : Camera;
        // dummy_camera.position.z = Cos (current_time * 0.2) * 100;
        dummy_camera.position.y = 130;
        dummy_camera.z_near = 2.0;
        dummy_camera.z_far = Chunk_Size * 4;
        dummy_camera.euler_angles.yaw = Cos (current_time * 0.2);
        // dummy_camera.euler_angles.pitch = Sin (current_time);
        dummy_camera.rotation = QuatfFromEulerAngles (dummy_camera.euler_angles);

        CalculateCameraMatrices (*dummy_camera);
        view_frustum := MakeViewFrustum (dummy_camera);

        DrawCameraFrustum (dummy_camera);
    }

    view_frustum := MakeViewFrustum (camera);

    chunks_to_draw : [..]*Chunk;
    chunks_to_draw.allocator = Temp;

    sqrd_render_distance := cast (float) (g_settings.render_distance * Chunk_Size);
    sqrd_render_distance *= sqrd_render_distance;
    for world.all_loaded_chunks
    {
        camera_horizontal_pos := Vec2f.{camera.position.x, camera.position.z};
        world_chunk_pos := Vec2f.{xx (it.x * Chunk_Size), xx (it.z * Chunk_Size)};

        if SqrdDistance (world_chunk_pos, camera_horizontal_pos) < sqrd_render_distance
        && (!g_settings.enable_view_culling || ChunkIsInFrustum (it, view_frustum))
        {
            ChunkGenerateMeshes (it);
            ArrayPush (*chunks_to_draw, it);
        }
    }

    g_chunks_drawn_this_frame = chunks_to_draw.count;

    GL_Utils.EnableBlock (GL_BLEND);
    GL_Utils.BlendFuncStateBlock ();
    GL_Utils.EnableBlock (GL_DEPTH_TEST);
    GL_Utils.EnableBlock (GL_CULL_FACE);
    GL_Utils.StateBlock (GL_ACTIVE_TEXTURE, (prev : GLenum) {glActiveTexture (prev);});
    GL_Utils.StateBlock (GL_TEXTURE_BINDING_2D_ARRAY, (prev : GLuint) {glBindTexture (GL_TEXTURE_2D_ARRAY, prev);});
    GL_Utils.StateBlock (GL_CURRENT_PROGRAM, (prev : GLuint) {glUseProgram (prev);});

    glBlendFunc (GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    glFrontFace (GL_CW);

    glActiveTexture (GL_TEXTURE0);
    glBindTexture (GL_TEXTURE_2D_ARRAY, g_texture_atlas);

    glActiveTexture (GL_TEXTURE1);
    glBindTexture (GL_TEXTURE_2D, g_grass_overlay_texture);

    glUseProgram (g_block_shader);

    loc := glGetUniformLocation (g_block_shader, "u_View_Projection_Matrix");
    glUniformMatrix4fv (loc, 1, GL_TRUE, *camera.view_projection_matrix.r0c0);

    loc = glGetUniformLocation (g_block_shader, "u_Texture_Atlases");
    glUniform1i (loc, 0);

    loc = glGetUniformLocation (g_block_shader, "u_Grass_Overlay");
    glUniform1i (loc, 1);

    for mesh_type : 0..ChunkMeshType.Count - 1
    {
        for chunks_to_draw
            DrawChunkMesh (it, camera, xx mesh_type);
    }
}
