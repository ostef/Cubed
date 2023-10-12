#module_parameters (
    Max_Vertices_Per_Draw_List := 10000,
    Max_Commands_Per_Draw_List := 100,
    Max_Shader_Params_Per_Command := 5
);

// @Todo: use indices to reduce memory usage

#import "Common";
#import "Linalg";

#load "gl.jai";

Vertex :: struct
{
    position : Vec2f;
    tex_coords : Vec2f;
    color : Vec4f;
}

ShaderHandle :: u32;

ShaderParam :: struct
{
    DataType :: enum u8
    {
        Int; Int2; Int3; Int4;
        Float; Float2; Float3; Float4;
        Mat3; Mat4;
    }

    location : s32;
    union
    {
        int_values : [4]s32;
        struct
        {
            xi, yi, zi, wi : s32;
        };
        float_values : [4]float;
        struct
        {
            x, y, z, w : float;
        };
        mat3 : Mat3f;
        mat4 : Mat4f;
    };
    data_type : DataType;
}

operator== :: (a : ShaderParam, b : ShaderParam) -> bool #must
{
    if a.data_type != b.data_type
        return false;

    if a.location != b.location
        return false;

    if #complete a.data_type ==
    {
    case .Float; #through;
    case .Int; return a.xi == b.xi;

    case .Float2; #through;
    case .Int2; return a.xi == b.xi && a.yi == b.yi;

    case .Float3; #through;
    case .Int3; return a.xi == b.xi && a.yi == b.yi && a.zi == b.zi;

    case .Float4; #through;
    case .Int4; return a.xi == b.xi && a.yi == b.yi && a.zi == b.zi && a.wi == b.wi;

    case .Mat3; return a.mat3 == b.mat3;
    case .Mat4; return a.mat4 == b.mat4;
    }
}

ShaderParam1i :: inline (location : s32, val : s32) -> ShaderParam #must
{
    result : ShaderParam = ---;
    result.location = location;
    result.xi = val;
    result.data_type = .Int;

    return result;
}

ShaderParam2i :: inline (location : s32, x : s32, y : s32) -> ShaderParam #must
{
    result : ShaderParam = ---;
    result.location = location;
    result.xi = x;
    result.yi = y;
    result.data_type = .Int2;

    return result;
}

ShaderParam3i :: inline (location : s32, x : s32, y : s32, z : s32) -> ShaderParam #must
{
    result : ShaderParam = ---;
    result.location = location;
    result.xi = x;
    result.yi = y;
    result.zi = z;
    result.data_type = .Int3;

    return result;
}

ShaderParam4i :: inline (location : s32, x : s32, y : s32, z : s32, w : s32) -> ShaderParam #must
{
    result : ShaderParam = ---;
    result.location = location;
    result.xi = x;
    result.yi = y;
    result.zi = z;
    result.wi = w;
    result.data_type = .Int4;

    return result;
}

ShaderParam1f :: inline (location : s32, val : float) -> ShaderParam #must
{
    result : ShaderParam = ---;
    result.location = location;
    result.x = val;
    result.data_type = .Float;

    return result;
}

ShaderParam2f :: inline (location : s32, x : float, y : float) -> ShaderParam #must
{
    result : ShaderParam = ---;
    result.location = location;
    result.x = x;
    result.y = y;
    result.data_type = .Float2;

    return result;
}

ShaderParam3f :: inline (location : s32, x : float, y : float, z : float) -> ShaderParam #must
{
    result : ShaderParam = ---;
    result.location = location;
    result.x = x;
    result.y = y;
    result.z = z;
    result.data_type = .Float3;

    return result;
}

ShaderParam4f :: inline (location : s32, x : float, y : float, z : float, w : float) -> ShaderParam #must
{
    result : ShaderParam = ---;
    result.location = location;
    result.x = x;
    result.y = y;
    result.z = z;
    result.w = w;
    result.data_type = .Float4;

    return result;
}

ShaderParamMat3 :: inline (location : s32, mat : Mat3) -> ShaderParam #must
{
    result : ShaderParam = ---;
    result.location = location;
    result.mat3 = mat;
    result.data_type = .Mat3;

    return result;
}

ShaderParamMat4 :: inline (location : s32, mat : Mat4) -> ShaderParam #must
{
    result : ShaderParam = ---;
    result.location = location;
    result.mat4 = mat;
    result.data_type = .Mat4;

    return result;
}

TextureHandle :: u32;

DrawCommand :: struct
{
    vertex_offset : s32;
    vertex_count  : s32;

    texture : TextureHandle;
    shader : ShaderHandle;
    shader_params : [Max_Shader_Params_Per_Command]ShaderParam;
    shader_param_count : s8;
}

DrawList :: struct
{
    next : *DrawList;
    command_count : s32;
    vertex_count : s32;
    commands : [Max_Commands_Per_Draw_List]DrawCommand = ---;
    vertices : [Max_Vertices_Per_Draw_List]Vertex = ---;
}

// @Todo: put this into the context for thread safety, handle threads

g_first_draw_list : *DrawList;
g_current_draw_list : *DrawList;

PushDrawList :: () -> *DrawList
{
    list := Alloc (DrawList);

    if !g_first_draw_list
    {
        g_first_draw_list = list;

        list.commands[0] = .{shader = GetDefaultShader ()};
    }
    else
    {
        g_current_draw_list.next = list;

        list.commands[0] = g_current_draw_list.commands[g_current_draw_list.command_count - 1];
    }

    g_current_draw_list = list;

    return list;
}

GetDrawList :: () -> *DrawList #must
{
    if !g_current_draw_list
        PushDrawList ();

    return g_current_draw_list;
}

PushDrawCommand :: () -> *DrawCommand #must
{
    list := GetDrawList ();

    if list.command_count >= Max_Commands_Per_Draw_List
        list = PushDrawList ();

    cmd := *list.commands[list.command_count];
    if list.command_count != 0
        cmd.* = list.commands[list.command_count - 1];

    cmd.vertex_offset = list.vertex_count;
    cmd.vertex_count = 0;

    list.command_count += 1;

    return cmd;
}

GetDrawCommand :: () -> *DrawCommand #must
{
    list := GetDrawList ();
    if list.command_count == 0
        return PushDrawCommand ();

    return *list.commands[list.command_count - 1];
}

GetTexture :: inline () -> TextureHandle #must
{
    return GetDrawCommand ().texture;
}

SetTexture :: inline (texture : TextureHandle)
{
    if GetTexture () == texture
        return;

    cmd := PushDrawCommand ();
    cmd.texture = texture;
}

GetShader :: inline () -> ShaderHandle #must
{
    return GetDrawCommand ().shader;
}

GetShaderParams :: inline () -> []ShaderParam #must
{
    result : []ShaderParam = ---;
    result.data = GetDrawCommand ().shader_params.data;
    result.count = GetDrawCommand ().shader_param_count;

    return result;
}

SetShader :: inline (shader : ShaderHandle, params : ..ShaderParam)
{
    Assert (params.count <= Max_Shader_Params_Per_Command);

    curr_params := GetShaderParams ();

    if GetShader () == shader && params.count == curr_params.count
    {
        same := true;
        for params
        {
            if it != curr_params[it_index]
            {
                same = false;
                break;
            }
        }

        if same
            return;
    }

    cmd := PushDrawCommand ();
    cmd.shader = shader;

    for params
        cmd.shader_params[it_index] = it;
    cmd.shader_param_count = xx params.count;
}

SetDefaultShader :: inline ()
{
    SetShader (GetDefaultShader ());
}

PushVertices :: (count : s32) -> *Vertex #must
{
    list := GetDrawList ();

    if list.vertex_count + count > Max_Vertices_Per_Draw_List
        list = PushDrawList ();

    vtx := *list.vertices[list.vertex_count];
    list.vertex_count += count;

    if list.command_count == 0
        list.command_count += 1;

    GetDrawCommand ().vertex_count += count;

    return vtx;
}

PushRect :: (min : Vec2f, max : Vec2f, color := Vec4f.{1,1,1,1}, uv_min := Vec2f.{0,0}, uv_max := Vec2f.{1,1})
{
    v := PushVertices (6);

    v.position = min;
    v.tex_coords = uv_min;
    v.color = color;

    v += 1;

    v.position = .{max.x, min.y};
    v.tex_coords = .{uv_max.x, uv_min.y};
    v.color = color;

    v += 1;

    v.position = max;
    v.tex_coords = uv_max;
    v.color = color;

    v += 1;

    v.position = min;
    v.tex_coords = uv_min;
    v.color = color;

    v += 1;

    v.position = .{min.x, max.y};
    v.tex_coords = .{uv_min.x, uv_max.y};
    v.color = color;

    v += 1;

    v.position = max;
    v.tex_coords = uv_max;
    v.color = color;
}
