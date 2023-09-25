#module_parameters (
    Max_Vertices_Per_Draw_List := 10000,
    Max_Commands_Per_Draw_List := 100
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

TextureHandle :: u32;

DrawCommand :: struct
{
    texture : TextureHandle;
    vertex_offset : s32;
    vertex_count  : s32;
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
        g_first_draw_list = list;
    else
        g_current_draw_list.next = list;

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
    Initialize (cmd);

    cmd.vertex_offset = list.vertex_count;

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

SetTexture :: (texture : TextureHandle)
{
    cmd := PushDrawCommand ();
    cmd.texture = texture;
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
