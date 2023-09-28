g_block_shader : GLuint;
g_foliage_shader : GLuint;
g_skinned_mesh_shader : GLuint;
g_static_mesh_shader : GLuint;

// We use a texture array of 6 textures to store our texture atlas for each side
// of the blocks. Atlas[BlockFace] is the texture atlas for a given block face

// Atlas is squared so below are both on X and Y axes
g_texture_atlas_size : s64;
g_atlas_cell_count : s64;
g_texture_atlas : GLuint;
g_all_texture_atlases : [6]GLuint; // We also have separate textures for each face, so we can display them using ImGui

g_grass_overlay_texture : GLuint;
g_destroy_stages_texture : GLuint;

g_block_shader_attribs : struct
{
    position : GLint;
    block_id : GLint;
    face : GLint;
    face_corner : GLint;
    block_height : GLint;
    temperature : GLint;
    humidity : GLint;
};

g_foliage_shader_attribs : struct
{
    position : GLint;
    normal : GLint;
    tex_coords : GLint;
    block_id : GLint;
    temperature : GLint;
    humidity : GLint;
};

g_steve_texture : GLuint;

g_framebuffers : struct
{
    all : [2]Framebuffer;

    #place all;
    main, first_person : Framebuffer;
};

Atlas_Cell_Size_No_Border :: 16;
Atlas_Cell_Border_Size :: 4;
Atlas_Cell_Size :: Atlas_Cell_Size_No_Border + Atlas_Cell_Border_Size * 2;

// @Todo: sample from a texture
Grass_Color_00 := Vec3f.{0.5372, 0.6980, 0.6078};
Grass_Color_10 := Vec3f.{0.7411, 0.7176, 0.3333};
Grass_Color_01 := Vec3f.{0.3333, 0.7764, 0.2509};
Grass_Color_11 := Vec3f.{0.3333, 0.7764, 0.2509};

StaticVertex :: struct
{
    position : Vec3f;
    normal : Vec3f;
    tex_coords : Vec2f;
}

BlockVertex :: struct
{
    position : Vec3f;
    block_height : float;
    temperature : float;
    humidity : float;
    face : BlockFace;
    corner : BlockFaceCorner;
    block_id : u8;
}

FoliageVertex :: struct
{
    position : Vec3f;
    normal : Vec3f;
    tex_coords : Vec2f;
    temperature : float;
    humidity : float;
    block_id : u8;
}

Max_Joints :: 1000;

GL_Skinning_Data_Uniform_Binding :: 1;

Block_Definitions_Shader_Export :: #string GLSL
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

ReloadShaders :: () -> bool
{
    GetAttribLocation :: inline (shader : GLuint, $name : string, location := #caller_location) -> GLint
    {
        loc := glGetAttribLocation (shader, name);
        if loc < 0
        {
            LogWarning ("Shader attribute % does not exist", name, location = location);
            LogMessage ("Note: shader attributes can get optimized out by OpenGL if they are not used in the shader");
        }

        return loc;
    }

    ProfileBlock ();
    AllocatorScope (Temp);

    block_ids_string : string;
    {
        builder : StringBuilder;

        for i : 0..BlockID.Count
            StringBuilderAppend (*builder, "const int Block_% = %;\n", i, cast (int) i);

        block_ids_string = StringBuilderBuild (*builder);
    }

    block_defs_export := FormatString (Block_Definitions_Shader_Export,
        Atlas_Cell_Size_No_Border, Atlas_Cell_Border_Size, g_atlas_cell_count,
        Grass_Color_00.r, Grass_Color_00.g, Grass_Color_00.b,
        Grass_Color_10.r, Grass_Color_10.g, Grass_Color_10.b,
        Grass_Color_01.r, Grass_Color_01.g, Grass_Color_01.b,
        Grass_Color_11.r, Grass_Color_11.g, Grass_Color_11.b,
        block_ids_string
    );

    shader_exports := ShaderProgramExport.[
        .{ "Block_Definitions", block_defs_export }
    ];

    {
        TemporaryStorageScope ();

        pp : ShaderPreprocessor;
        InitShaderPreprocessor (*pp, "shaders/block.glsl", shader_exports);
        ok, vertex_source, geometry_source, fragment_source := PreprocessShaderSource (*pp);
        if !ok
            return false;

        new_shader := GL_Utils.CreateShaderProgram (vertex_source, fragment_source, geometry_source, print_shader_on_error = false);
        if !new_shader
            return false;

        attribs : type_of (g_block_shader_attribs);
        attribs.position = GetAttribLocation (new_shader, "a_Position");
        attribs.block_id = GetAttribLocation (new_shader, "a_Block_Id");
        attribs.face = GetAttribLocation (new_shader, "a_Face");
        attribs.face_corner = GetAttribLocation (new_shader, "a_Face_Corner");
        attribs.block_height = GetAttribLocation (new_shader, "a_Block_Height");
        attribs.temperature = GetAttribLocation (new_shader, "a_Temperature");
        attribs.humidity = GetAttribLocation (new_shader, "a_Humidity");

        glDeleteProgram (g_block_shader);
        g_block_shader = new_shader;
        g_block_shader_attribs = attribs;
    }

    {
        TemporaryStorageScope ();

        pp : ShaderPreprocessor;
        InitShaderPreprocessor (*pp, "shaders/foliage.glsl", shader_exports);
        ok, vertex_source, geometry_source, fragment_source := PreprocessShaderSource (*pp);
        if !ok
            return false;

        new_shader := GL_Utils.CreateShaderProgram (vertex_source, fragment_source, geometry_source, print_shader_on_error = false);
        if !new_shader
            return false;

        attribs : type_of (g_foliage_shader_attribs);
        attribs.position = GetAttribLocation (new_shader, "a_Position");
        attribs.normal = GetAttribLocation (new_shader, "a_Normal");
        attribs.tex_coords = GetAttribLocation (new_shader, "a_Tex_Coords");
        attribs.block_id = GetAttribLocation (new_shader, "a_Block_Id");
        attribs.temperature = GetAttribLocation (new_shader, "a_Temperature");
        attribs.humidity = GetAttribLocation (new_shader, "a_Humidity");

        glDeleteProgram (g_foliage_shader);
        g_foliage_shader = new_shader;
        g_foliage_shader_attribs = attribs;
    }

    {
        TemporaryStorageScope ();

        pp : ShaderPreprocessor;
        InitShaderPreprocessor (*pp, "shaders/skinned_mesh.glsl", shader_exports);
        ok, vertex_source, geometry_source, fragment_source := PreprocessShaderSource (*pp);
        if !ok
            return false;

        new_shader := GL_Utils.CreateShaderProgram (vertex_source, fragment_source, geometry_source, print_shader_on_error = false);
        if !new_shader
            return false;

        glDeleteProgram (g_skinned_mesh_shader);
        g_skinned_mesh_shader = new_shader;

        uniform_block_size : s32;
        glGetIntegerv (GL_MAX_UNIFORM_BLOCK_SIZE, *uniform_block_size);
        if uniform_block_size < Max_Joints * size_of (Mat4f)
        {
            LogError ("OpenGL error: maximum uniform block size is too small to hold the skinning data for % joints", Max_Joints);
            return false;
        }

        skinning_data_uniform_index := glGetUniformBlockIndex (g_skinned_mesh_shader, "Skinning_Data");
        glUniformBlockBinding (g_skinned_mesh_shader, skinning_data_uniform_index, GL_Skinning_Data_Uniform_Binding);
    }

    {
        TemporaryStorageScope ();

        pp : ShaderPreprocessor;
        InitShaderPreprocessor (*pp, "shaders/static_mesh.glsl", shader_exports);
        ok, vertex_source, geometry_source, fragment_source := PreprocessShaderSource (*pp);
        if !ok
            return false;

        new_shader := GL_Utils.CreateShaderProgram (vertex_source, fragment_source, geometry_source, print_shader_on_error = false);
        if !new_shader
            return false;

        glDeleteProgram (g_static_mesh_shader);
        g_static_mesh_shader = new_shader;
    }

    return true;
}

DrawInit :: (textures_directory : string, width : s32, height : s32) -> bool
{
    if !LoadTextureAtlases (textures_directory)
    {
        LogError ("Could not load textures at %", textures_directory);
        return false;
    }

    steve_filename := FormatToCString ("%/steve.png", textures_directory);
    g_steve_texture = LoadSingleTexture (steve_filename);
    if !g_steve_texture
    {
        LogError ("Could not load texture steve.png");
        return false;
    }

    if !ReloadShaders ()
        return false;

    for * g_framebuffers.all
    {
        if !CreateFramebuffer (it, width, height)
        {
            LogError ("Could not create framebuffer %", it_index);
            return false;
        }
    }

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
        "grass",
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

    g_destroy_stages_texture = LoadSingleTexture (FormatToCString (Temp, "%/destroy_stages.png", textures_dirname));
    if !g_destroy_stages_texture
    {
        LogError ("Could not load texture destroy_stages.png");
        return false;
    }

    LogContentMessage ("Loaded texture atlas: % cells, % by % pixels", g_atlas_cell_count, g_texture_atlas_size, g_texture_atlas_size);

    return true;
}

DrawSkinnedMesh :: inline (mesh : SkinnedMesh, pose : SkeletonPose, camera : Camera, model_matrix : Mat4f)
{
    GL_Utils.StateBlock (GL_VERTEX_ARRAY_BINDING, (prev : GLuint) {glBindVertexArray (prev);});
    GL_Utils.StateBlock (GL_ARRAY_BUFFER_BINDING, (prev : GLuint) {glBindBuffer (GL_ARRAY_BUFFER, prev);});
    GL_Utils.StateBlock (GL_ELEMENT_ARRAY_BUFFER_BINDING, (prev : GLuint) {glBindBuffer (GL_ELEMENT_ARRAY_BUFFER, prev);});
    GL_Utils.StateBlock (GL_UNIFORM_BUFFER_BINDING, (prev : GLuint) {glBindBuffer (GL_UNIFORM_BUFFER, prev);});
    GL_Utils.StateBlock (GL_CURRENT_PROGRAM, (prev : GLuint) {glUseProgram (prev);});

    GL_Utils.EnableBlock (GL_DEPTH_TEST);
    GL_Utils.EnableBlock (GL_CULL_FACE);

    glUseProgram (g_skinned_mesh_shader);

    loc := glGetUniformLocation (g_skinned_mesh_shader, "u_View_Projection_Matrix");
    glUniformMatrix4fv (loc, 1, GL_TRUE, *camera.view_projection_matrix.r0c0);

    loc = glGetUniformLocation (g_skinned_mesh_shader, "u_Model_Matrix");
    glUniformMatrix4fv (loc, 1, GL_TRUE, *model_matrix.r0c0);

    glBindVertexArray (mesh.vao);
    glBindBuffer (GL_ARRAY_BUFFER, mesh.vbo);
    glBindBuffer (GL_ELEMENT_ARRAY_BUFFER, mesh.ibo);
    glBindBufferBase (GL_UNIFORM_BUFFER, GL_Skinning_Data_Uniform_Binding, pose.skinning_data_ubo);

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

PushDestroyingBlockVertices :: (
    vertices : *[..]StaticVertex,
    position : Vec3f,
    block_height : float,
    breaking_stage : u8
)
{
    Inflate_Amount :: 0.0008;

    PushVertex :: (face : BlockFace, corner : BlockFaceCorner) -> *StaticVertex #must #expand
    {
        v := ArrayPush (`vertices);
        v.position = `position - .{Inflate_Amount, Inflate_Amount, Inflate_Amount};

        if #complete face ==
        {
        case .East;  v.normal = .{ 1,0,0};
        case .West;  v.normal = .{-1,0,0};
        case .Above; v.normal = .{0, 1,0};
        case .Below; v.normal = .{0,-1,0};
        case .North; v.normal = .{0,0, 1};
        case .South; v.normal = .{0,0,-1};
        }

        if #complete corner ==
        {
        case .Top_Left;
            if face != .Above && face != .Below
                v.tex_coords.y = 1 - `block_height;
            v.tex_coords.x = 0;

        case .Top_Right;
            if face != .Above && face != .Below
                v.tex_coords.y = 1 - `block_height;
            v.tex_coords.x = 1;

        case .Bottom_Left;
            v.tex_coords.x = 0;
            v.tex_coords.y = 1;

        case .Bottom_Right;
            v.tex_coords.x = 1;
            v.tex_coords.y = 1;
        }

        v.tex_coords.x += `breaking_stage;
        v.tex_coords.x /= 10;

        return v;
    }

    // East
    {
        v := PushVertex (.East, .Bottom_Left);
        v.position += Vec3f.{1, 0, 0} * (1 + 2 * Inflate_Amount);

        v = PushVertex (.East, .Top_Left);
        v.position += Vec3f.{1, block_height, 0} * (1 + 2 * Inflate_Amount);

        v = PushVertex (.East, .Top_Right);
        v.position += Vec3f.{1, block_height, 1} * (1 + 2 * Inflate_Amount);

        v = PushVertex (.East, .Bottom_Left);
        v.position += Vec3f.{1, 0, 0} * (1 + 2 * Inflate_Amount);

        v = PushVertex (.East, .Top_Right);
        v.position += Vec3f.{1, block_height, 1} * (1 + 2 * Inflate_Amount);

        v = PushVertex (.East, .Bottom_Right);
        v.position += Vec3f.{1, 0, 1} * (1 + 2 * Inflate_Amount);
    }

    // West
    {
        v := PushVertex (.West, .Bottom_Right);
        v.position += Vec3f.{0, 0, 0} * (1 + 2 * Inflate_Amount);

        v = PushVertex (.West, .Top_Left);
        v.position += Vec3f.{0, block_height, 1} * (1 + 2 * Inflate_Amount);

        v = PushVertex (.West, .Top_Right);
        v.position += Vec3f.{0, block_height, 0} * (1 + 2 * Inflate_Amount);

        v = PushVertex (.West, .Bottom_Right);
        v.position += Vec3f.{0, 0, 0} * (1 + 2 * Inflate_Amount);

        v = PushVertex (.West, .Bottom_Left);
        v.position += Vec3f.{0, 0, 1} * (1 + 2 * Inflate_Amount);

        v = PushVertex (.West, .Top_Left);
        v.position += Vec3f.{0, block_height, 1} * (1 + 2 * Inflate_Amount);
    }

    // Above
    {
        v := PushVertex (.Above, .Bottom_Left);
        v.position += Vec3f.{0, block_height, 0} * (1 + 2 * Inflate_Amount);

        v = PushVertex (.Above, .Top_Right);
        v.position += Vec3f.{1, block_height, 1} * (1 + 2 * Inflate_Amount);

        v = PushVertex (.Above, .Bottom_Right);
        v.position += Vec3f.{1, block_height, 0} * (1 + 2 * Inflate_Amount);

        v = PushVertex (.Above, .Bottom_Left);
        v.position += Vec3f.{0, block_height, 0} * (1 + 2 * Inflate_Amount);

        v = PushVertex (.Above, .Top_Left);
        v.position += Vec3f.{0, block_height, 1} * (1 + 2 * Inflate_Amount);

        v = PushVertex (.Above, .Top_Right);
        v.position += Vec3f.{1, block_height, 1} * (1 + 2 * Inflate_Amount);
    }

    // Below
    {
        v := PushVertex (.Below, .Top_Left);
        v.position += Vec3f.{0, 0, 0} * (1 + 2 * Inflate_Amount);

        v = PushVertex (.Below, .Top_Right);
        v.position += Vec3f.{1, 0, 0} * (1 + 2 * Inflate_Amount);

        v = PushVertex (.Below, .Bottom_Right);
        v.position += Vec3f.{1, 0, 1} * (1 + 2 * Inflate_Amount);

        v = PushVertex (.Below, .Top_Left);
        v.position += Vec3f.{0, 0, 0} * (1 + 2 * Inflate_Amount);

        v = PushVertex (.Below, .Bottom_Right);
        v.position += Vec3f.{1, 0, 1} * (1 + 2 * Inflate_Amount);

        v = PushVertex (.Below, .Bottom_Left);
        v.position += Vec3f.{0, 0, 1} * (1 + 2 * Inflate_Amount);
    }

    // North
    {
        v := PushVertex (.North, .Bottom_Right);
        v.position += Vec3f.{0, 0, 1} * (1 + 2 * Inflate_Amount);

        v = PushVertex (.North, .Bottom_Left);
        v.position += Vec3f.{1, 0, 1} * (1 + 2 * Inflate_Amount);

        v = PushVertex (.North, .Top_Left);
        v.position += Vec3f.{1, block_height, 1} * (1 + 2 * Inflate_Amount);

        v = PushVertex (.North, .Bottom_Right);
        v.position += Vec3f.{0, 0, 1} * (1 + 2 * Inflate_Amount);

        v = PushVertex (.North, .Top_Left);
        v.position += Vec3f.{1, block_height, 1} * (1 + 2 * Inflate_Amount);

        v = PushVertex (.North, .Top_Right);
        v.position += Vec3f.{0, block_height, 1} * (1 + 2 * Inflate_Amount);
    }

    // South
    {
        v := PushVertex (.South, .Bottom_Left);
        v.position += Vec3f.{0, 0, 0} * (1 + 2 * Inflate_Amount);

        v = PushVertex (.South, .Top_Right);
        v.position += Vec3f.{1, block_height, 0} * (1 + 2 * Inflate_Amount);

        v = PushVertex (.South, .Bottom_Right);
        v.position += Vec3f.{1, 0, 0} * (1 + 2 * Inflate_Amount);

        v = PushVertex (.South, .Bottom_Left);
        v.position += Vec3f.{0, 0, 0} * (1 + 2 * Inflate_Amount);

        v = PushVertex (.South, .Top_Left);
        v.position += Vec3f.{0, block_height, 0} * (1 + 2 * Inflate_Amount);

        v = PushVertex (.South, .Top_Right);
        v.position += Vec3f.{1, block_height, 0} * (1 + 2 * Inflate_Amount);
    }
}

DrawWorld :: (world : *World, camera : Camera)
{
    view_frustum := MakeViewFrustum (camera, cast (float) (g_settings.render_distance + 1) * Chunk_Size);

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
        if mesh_type == ChunkMeshType.Foliage
        {
            glDisable (GL_CULL_FACE);

            glUseProgram (g_foliage_shader);

            loc = glGetUniformLocation (g_foliage_shader, "u_View_Projection_Matrix");
            glUniformMatrix4fv (loc, 1, GL_TRUE, *camera.view_projection_matrix.r0c0);

            loc = glGetUniformLocation (g_foliage_shader, "u_Texture_Atlases");
            glUniform1i (loc, 0);
        }

        for chunks_to_draw
            DrawChunkMesh (it, camera, xx mesh_type);
    }

    glActiveTexture (GL_TEXTURE0);
    glBindTexture (GL_TEXTURE_2D, g_destroy_stages_texture);

    glUseProgram (g_static_mesh_shader);

    loc = glGetUniformLocation (g_static_mesh_shader, "u_View_Projection_Matrix");
    glUniformMatrix4fv (loc, 1, GL_TRUE, *camera.view_projection_matrix.r0c0);

    model_matrix : Mat4f;
    loc = glGetUniformLocation (g_static_mesh_shader, "u_Model_Matrix");
    glUniformMatrix4fv (loc, 1, GL_TRUE, *model_matrix.r0c0);

    loc = glGetUniformLocation (g_static_mesh_shader, "u_Use_Texture");
    glUniform1i (loc, 1);

    loc = glGetUniformLocation (g_static_mesh_shader, "u_Color");
    glUniform4f (loc, 1, 1, 1, 1);

    destroying_blocks_vertices : [..]StaticVertex;
    destroying_blocks_vertices.allocator = Temp;
    ArrayReserve (*destroying_blocks_vertices, 6 * 6 * world.blocks_being_destroyed.count);

    for world.blocks_being_destroyed
    {
        chunk_x, chunk_z := ChunkPositionFromWorldPosition (it.x, it.z);
        chunk := WorldGetChunk (world, chunk_x, chunk_z);
        if !chunk
            continue;

        rel_x, rel_z := ChunkAbsoluteToRelativeCoordinates (chunk_x, chunk_z, it.x, it.z);
        height := BlockGetHeight (chunk, rel_x, it.y, rel_z);
        PushDestroyingBlockVertices (*destroying_blocks_vertices, .{xx it.x, xx it.y, xx it.z}, height, cast (u8) it.stage);
    }

    glBindVertexArray (world.blocks_being_destroyed_vao);
    glBindBuffer (GL_ARRAY_BUFFER, world.blocks_being_destroyed_vbo);
    glBufferData (GL_ARRAY_BUFFER, size_of (StaticVertex) * destroying_blocks_vertices.count, destroying_blocks_vertices.data, GL_DYNAMIC_DRAW);

    glDrawArrays (GL_TRIANGLES, 0, xx destroying_blocks_vertices.count);
}

DrawBlockOutline :: (position : Vec3f, min : Vec3f, max : Vec3f, color : Vec4f, camera : Camera)
{
    GL_Utils.StateBlock (GL_VERTEX_ARRAY_BINDING, (prev : GLuint) {glBindVertexArray (prev);});
    GL_Utils.StateBlock (GL_ARRAY_BUFFER_BINDING, (prev : GLuint) {glBindBuffer (GL_ARRAY_BUFFER, prev);});

    if !g_block_outline_vao
    {
        InitBlockOutlineGLObjects ();
    }
    else
    {
        glBindVertexArray (g_block_outline_vao);
        glBindBuffer (GL_ARRAY_BUFFER, g_block_outline_vbo);
    }

    GL_Utils.EnableBlock (GL_BLEND);
    GL_Utils.BlendFuncStateBlock ();
    GL_Utils.EnableBlock (GL_DEPTH_TEST);
    GL_Utils.DisableBlock (GL_CULL_FACE);
    GL_Utils.StateBlock (GL_CURRENT_PROGRAM, (prev : GLuint) {glUseProgram (prev);});

    glBlendFunc (GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    glUseProgram (g_static_mesh_shader);

    loc := glGetUniformLocation (g_static_mesh_shader, "u_View_Projection_Matrix");
    glUniformMatrix4fv (loc, 1, GL_TRUE, *camera.view_projection_matrix.r0c0);

    Inflate_Amount :: 0.003;

    inflation := Vec3f.{Inflate_Amount,Inflate_Amount,Inflate_Amount};
    size := max - min;

    model_matrix :=
        Mat4fTranslate (position + min - inflation * 0.5)
        * Mat4fScale (size + inflation);

    loc = glGetUniformLocation (g_static_mesh_shader, "u_Model_Matrix");
    glUniformMatrix4fv (loc, 1, GL_TRUE, *model_matrix.r0c0);

    loc = glGetUniformLocation (g_static_mesh_shader, "u_Use_Texture");
    glUniform1i (loc, 0);

    loc = glGetUniformLocation (g_static_mesh_shader, "u_Color");
    glUniform4f (loc, color.r, color.g, color.b, color.a);

    glLineWidth (2.5);

    glDrawArrays (GL_LINES, 0, Block_Outline_Vertices.count);
}

#scope_file

g_block_outline_vao, g_block_outline_vbo : GLuint;

Block_Outline_Vertices :: StaticVertex.[
    //
    .{position = .{0,0,0}},
    .{position = .{0,1,0}},

    .{position = .{0,0,0}},
    .{position = .{1,0,0}},

    .{position = .{1,0,0}},
    .{position = .{1,1,0}},

    .{position = .{1,1,0}},
    .{position = .{0,1,0}},

    //
    .{position = .{0,0,1}},
    .{position = .{0,1,1}},

    .{position = .{0,0,1}},
    .{position = .{1,0,1}},

    .{position = .{1,0,1}},
    .{position = .{1,1,1}},

    .{position = .{1,1,1}},
    .{position = .{0,1,1}},

    //
    .{position = .{0,0,0}},
    .{position = .{0,0,1}},

    .{position = .{0,1,0}},
    .{position = .{0,1,1}},

    //
    .{position = .{1,0,0}},
    .{position = .{1,0,1}},

    .{position = .{1,1,0}},
    .{position = .{1,1,1}}
];


InitBlockOutlineGLObjects :: ()
{
    glGenVertexArrays (1, *g_block_outline_vao);
    glGenBuffers (1, *g_block_outline_vbo);

    glBindVertexArray (g_block_outline_vao);
    glBindBuffer (GL_ARRAY_BUFFER, g_block_outline_vbo);

    glBufferData (GL_ARRAY_BUFFER, size_of (type_of (Block_Outline_Vertices)), Block_Outline_Vertices.data, GL_STATIC_DRAW);

    glEnableVertexAttribArray (0);
    glVertexAttribPointer (0, 3, GL_FLOAT, GL_FALSE, size_of (StaticVertex), cast (*void) OffsetOf (StaticVertex, "position"));

    glEnableVertexAttribArray (1);
    glVertexAttribPointer (1, 3, GL_FLOAT, GL_FALSE, size_of (StaticVertex), cast (*void) OffsetOf (StaticVertex, "normal"));

    glEnableVertexAttribArray (2);
    glVertexAttribPointer (2, 2, GL_FLOAT, GL_FALSE, size_of (StaticVertex), cast (*void) OffsetOf (StaticVertex, "tex_coords"));
}

#scope_export
