#scope_file

DebugVertex :: struct
{
    position : Vec3f;
    color : Vec4f;
}

g_debug_draw_initialized : bool;
g_debug_draw_shader : GLuint;
g_debug_draw_vertices : [10000]DebugVertex;
g_debug_draw_vertex_count : s64;
g_debug_draw_vao, g_debug_draw_vbo : GLuint;

EnsureInit :: ()
{
    HandleShaderFailure :: inline (shader : GLuint, name : string, $is_shader := true)
    {
        status : s32;
        #if is_shader
            glGetShaderiv (shader, GL_COMPILE_STATUS, *status);
        else
            glGetProgramiv (shader, GL_LINK_STATUS, *status);

        if !status
        {
            log_length : s32;
            #if is_shader
                glGetShaderiv (shader, GL_INFO_LOG_LENGTH, *log_length);
            else
                glGetProgramiv (shader, GL_INFO_LOG_LENGTH, *log_length);

            info_log := Alloc (u8, log_length + 1);
            #if is_shader
                glGetShaderInfoLog (shader, xx (log_length + 1), xx *log_length, info_log);
            else
                glGetProgramInfoLog (shader, xx (log_length + 1), xx *log_length, info_log);

            Panic ("Could not compile % for debug drawing:\n%", name, MakeString (log_length, info_log));
        }
    }
    status : s32;

    if g_debug_draw_initialized
        return;

    g_debug_draw_shader = GL_Utils.CreateShaderProgram (Vertex_Shader, Fragment_Shader);

    glGenVertexArrays (1, *g_debug_draw_vao);
    glBindVertexArray (g_debug_draw_vao);

    glGenBuffers (1, *g_debug_draw_vbo);
    glBindBuffer (GL_ARRAY_BUFFER, g_debug_draw_vbo);

    glEnableVertexAttribArray (0);
    glVertexAttribPointer (0, 3, GL_FLOAT, false, size_of (DebugVertex), cast (*void) OffsetOf (DebugVertex, "position"));

    glEnableVertexAttribArray (1);
    glVertexAttribPointer (1, 4, GL_FLOAT, false, size_of (DebugVertex), cast (*void) OffsetOf (DebugVertex, "color"));

    glBindVertexArray (0);
    glBindBuffer (GL_ARRAY_BUFFER, 0);

    g_debug_draw_initialized = true;
}

Vertex_Shader :: #string GLSL
#version 330 core

layout (location = 0) in vec3 vtx_position;
layout (location = 1) in vec4 vtx_color;

out vec4 color;

uniform mat4 view_projection_matrix;

void main ()
{
    gl_Position = view_projection_matrix * vec4 (vtx_position, 1);
    color = vtx_color;
}
GLSL

Fragment_Shader :: #string GLSL
#version 330 core

in vec4 color;

out vec4 frag_color;

void main ()
{
    frag_color = color;
}
GLSL

#scope_export

DebugDrawFlush :: ()
{
    EnsureInit ();

    if g_debug_draw_vertex_count == 0
        return;

    defer g_debug_draw_vertex_count = 0;

    GL_Utils.EnableBlock (GL_DEPTH_TEST);
    GL_Utils.StateBlock (GL_VERTEX_ARRAY_BINDING, (prev : GLuint) {glBindVertexArray (prev);});
    GL_Utils.StateBlock (GL_ARRAY_BUFFER_BINDING, (prev : GLuint) {glBindBuffer (GL_ARRAY_BUFFER, prev);});
    GL_Utils.StateBlock (GL_CURRENT_PROGRAM, (prev : GLuint) {glUseProgram (prev);});

    glBindVertexArray (g_debug_draw_vao);
    glBindBuffer (GL_ARRAY_BUFFER, g_debug_draw_vbo);
    glUseProgram (g_debug_draw_shader);

    vpm_loc := glGetUniformLocation (g_debug_draw_shader, "view_projection_matrix");
    glUniformMatrix4fv (vpm_loc, 1, GL_TRUE, *g_camera.view_projection_matrix.r0c0);

    glBufferData (GL_ARRAY_BUFFER, size_of (DebugVertex) * g_debug_draw_vertex_count, g_debug_draw_vertices.data, GL_DYNAMIC_DRAW);

    glDrawArrays (GL_LINES, 0, xx g_debug_draw_vertex_count);
}

DebugDrawLine :: (start : Vec3f, end : Vec3f, color : Vec4f)
{
    EnsureInit ();

    if g_debug_draw_vertex_count >= g_debug_draw_vertices.count
        DebugDrawFlush ();

    i := g_debug_draw_vertex_count;

    g_debug_draw_vertices[i].position = start;
    g_debug_draw_vertices[i].color = color;
    i += 1;

    g_debug_draw_vertices[i].position = end;
    g_debug_draw_vertices[i].color = color;
    i += 1;

    g_debug_draw_vertex_count = i;
}

DebugDrawWireframeAABB :: (min : Vec3f, max : Vec3f, color : Vec4f)
{
    EnsureInit ();

    DebugDrawLine (.{min.x, min.y, min.z}, .{max.x, min.y, min.z}, color);
    DebugDrawLine (.{min.x, min.y, max.z}, .{max.x, min.y, max.z}, color);
    DebugDrawLine (.{min.x, max.y, max.z}, .{max.x, max.y, max.z}, color);
    DebugDrawLine (.{min.x, max.y, min.z}, .{max.x, max.y, min.z}, color);

    DebugDrawLine (.{min.x, max.y, min.z}, .{min.x, max.y, max.z}, color);
    DebugDrawLine (.{min.x, min.y, min.z}, .{min.x, min.y, max.z}, color);
    DebugDrawLine (.{max.x, min.y, min.z}, .{max.x, min.y, max.z}, color);
    DebugDrawLine (.{max.x, max.y, min.z}, .{max.x, max.y, max.z}, color);

    DebugDrawLine (.{min.x, min.y, min.z}, .{min.x, max.y, min.z}, color);
    DebugDrawLine (.{min.x, min.y, max.z}, .{min.x, max.y, max.z}, color);
    DebugDrawLine (.{max.x, min.y, max.z}, .{max.x, max.y, max.z}, color);
    DebugDrawLine (.{max.x, min.y, min.z}, .{max.x, max.y, min.z}, color);
}

DebugDrawSkeletonPose :: (pose : SkeletonPose, transform : Mat4f, color : Vec4f)
{
    joint_names := GetJointNamesArray (pose.skeleton);

    for pose.joints
    {
        parent_transform := ifx it.parent
            then transform * it.parent.model_space_transform
            else transform;

        world_space_transform := transform * it.model_space_transform;
        start := TranslationVector (parent_transform);
        end   := TranslationVector (world_space_transform);

        Im3d.DrawLine (start, end, 1, .{0xffffffff});
        Im3d.DrawLine (end, end + RightVector (world_space_transform) * 0.1, 1, .{0xff0000ff});
        Im3d.DrawLine (end, end + UpVector (world_space_transform) * 0.1, 1, .{0x00ff00ff});
        Im3d.DrawLine (end, end + ForwardVector (world_space_transform) * 0.1, 1, .{0x0000ffff});

        joint_name := GetJointName (pose.skeleton, xx it_index);
        Im3d.Text (end, 1, .{0xffffffff}, cast (u32) Im3d.TextFlags.Default, joint_name.data);
    }
}
