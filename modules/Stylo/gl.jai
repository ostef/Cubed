#scope_file

g_gl_initialized : bool;
g_vao, g_vbo : u32;
g_shader : u32;

#scope_export

GetDefaultShader :: inline () -> ShaderHandle #must
{
    return cast (ShaderHandle) g_shader;
}

GL_Vertex_Shader :: #string GLSL
#version 330 core

layout (location = 0) in vec2 a_Position;
layout (location = 1) in vec2 a_Tex_Coords;
layout (location = 2) in vec4 a_Color;

out vec2 Tex_Coords;
out vec4 Color;

uniform mat4 u_View_Projection_Matrix;

void main ()
{
    gl_Position = u_View_Projection_Matrix * vec4 (a_Position, 0, 1);
    Tex_Coords = a_Tex_Coords;
    Color = a_Color;
}
GLSL

GL_Fragment_Shader :: #string GLSL
#version 330 core

in vec2 Tex_Coords;
in vec4 Color;

out vec4 Frag_Color;

uniform sampler2D u_Texture;
uniform bool u_Use_Texture;

void main ()
{
    if (u_Use_Texture)
        Frag_Color = texture (u_Texture, Tex_Coords) * Color;
    else
        Frag_Color = Color;
}
GLSL

SetShaderParam :: inline (param : ShaderParam)
{
    if #complete param.data_type ==
    {
    case .Int; glUniform1i (param.location, param.xi);
    case .Int2; glUniform2i (param.location, param.xi, param.yi);
    case .Int3; glUniform3i (param.location, param.xi, param.yi, param.zi);
    case .Int4; glUniform4i (param.location, param.xi, param.yi, param.zi, param.wi);
    case .Float; glUniform1f (param.location, param.x);
    case .Float2; glUniform2f (param.location, param.x, param.y);
    case .Float3; glUniform3f (param.location, param.x, param.y, param.z);
    case .Float4; glUniform4f (param.location, param.x, param.y, param.z, param.w);
    case .Mat3; glUniformMatrix3fv (param.location, 1, GL_TRUE, *param.mat3.r0c0);
    case .Mat4; glUniformMatrix4fv (param.location, 1, GL_TRUE, *param.mat4.r0c0);
    }
}

GLRenderDrawLists :: (width : s32, height : s32)
{
    #import "GL";
    GL_Utils :: #import "GL_Utils";

    GL_Utils.StateBlock (GL_VERTEX_ARRAY_BINDING, (prev : GLuint) {glBindVertexArray (prev);});
    GL_Utils.StateBlock (GL_ARRAY_BUFFER_BINDING, (prev : GLuint) {glBindBuffer (GL_ARRAY_BUFFER, prev);});

    if !g_gl_initialized
    {
        glGenVertexArrays (1, *g_vao);
        glGenBuffers (1, *g_vbo);
        Assert (g_vao != 0, "Stylo: glGenVertexArrays failed");
        Assert (g_vbo != 0, "Stylo: glGenBuffers failed");

        glBindVertexArray (g_vao);
        glBindBuffer (GL_ARRAY_BUFFER, g_vbo);

        glEnableVertexAttribArray (0);
        glVertexAttribPointer (0, 2, GL_FLOAT, GL_FALSE, size_of (Vertex), cast (*void) OffsetOf (Vertex, "position"));

        glEnableVertexAttribArray (1);
        glVertexAttribPointer (1, 2, GL_FLOAT, GL_FALSE, size_of (Vertex), cast (*void) OffsetOf (Vertex, "tex_coords"));

        glEnableVertexAttribArray (2);
        glVertexAttribPointer (2, 4, GL_FLOAT, GL_FALSE, size_of (Vertex), cast (*void) OffsetOf (Vertex, "color"));

        glBufferData (GL_ARRAY_BUFFER, size_of (Vertex) * Max_Vertices_Per_Draw_List, null, GL_DYNAMIC_DRAW);

        g_shader = GL_Utils.CreateShaderProgram (GL_Vertex_Shader, GL_Fragment_Shader);
        Assert (g_shader != 0, "Could not create shader program");

        g_gl_initialized = true;
    }
    else
    {
        glBindVertexArray (g_vao);
        glBindBuffer (GL_ARRAY_BUFFER, g_vbo);
    }

    GL_Utils.EnableBlock (GL_BLEND);
    GL_Utils.BlendFuncStateBlock ();
    GL_Utils.DisableBlock (GL_DEPTH_TEST);
    GL_Utils.DisableBlock (GL_CULL_FACE);
    GL_Utils.StateBlock (GL_ACTIVE_TEXTURE, (prev : GLenum) {glActiveTexture (prev);});
    GL_Utils.StateBlock (GL_TEXTURE_BINDING_2D, (prev : GLuint) {glBindTexture (GL_TEXTURE_2D, prev);});
    GL_Utils.StateBlock (GL_CURRENT_PROGRAM, (prev : GLuint) {glUseProgram (prev);});

    glBlendFunc (GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    glActiveTexture (GL_TEXTURE0);

    prev_shader : GLuint = 0;
    loc_use_texture : GLint;

    #if Origin_Top_Left
        view_projection_matrix := mat4f_orthographic_projection (0, xx width, xx height, 0, 0, 1);
    else
        view_projection_matrix := mat4f_orthographic_projection (0, xx width, 0, xx height, 0, 1);

    list := g_first_draw_list;
    while list
    {
        next := list.next;

        glBufferSubData (GL_ARRAY_BUFFER, 0, size_of (Vertex) * list.vertex_count, list.vertices.data);

        for cmd_i : 0..list.command_count - 1
        {
            cmd := list.commands[cmd_i];

            if cmd.vertex_count == 0
                continue;

            if !cmd.shader
                continue;

            if cmd.shader != prev_shader
            {
                glUseProgram (cmd.shader);

                loc_view_proj := glGetUniformLocation (cmd.shader, "u_View_Projection_Matrix");
                loc_viewport_size := glGetUniformLocation (cmd.shader, "u_Viewport_Size");
                loc_texture := glGetUniformLocation (cmd.shader, "u_Texture");
                loc_use_texture = glGetUniformLocation (cmd.shader, "u_Use_Texture");

                glUniformMatrix4fv (loc_view_proj, 1, GL_TRUE, *view_projection_matrix.r0c0);
                glUniform2f (loc_viewport_size, cast (float) width, cast (float) height);
                glUniform1i (loc_texture, 0);

                prev_shader = cmd.shader;
            }

            for i : 0..cmd.shader_param_count - 1
            {
                SetShaderParam (cmd.shader_params[i]);
            }

            glUniform1i (loc_use_texture, cast (s32) (cmd.texture != 0));
            glBindTexture (GL_TEXTURE_2D, cmd.texture);

            glDrawArrays (GL_TRIANGLES, cmd.vertex_offset, cast (u32) cmd.vertex_count);
        }

        Free (list);
        list = next;
    }

    g_first_draw_list = null;
    g_current_draw_list = null;
}

CreateTexture :: (width : u32, height : u32, data : *void) -> TextureHandle #must
{
    #import "GL";
    GL_Utils :: #import "GL_Utils";

    GL_Utils.StateBlock (GL_TEXTURE_BINDING_2D, (prev : GLuint) {glBindTexture (GL_TEXTURE_2D, prev);});

    result : GLuint;
    glGenTextures (1, *result);
    glBindTexture (GL_TEXTURE_2D, result);

    glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

    glTexImage2D (GL_TEXTURE_2D, 0, GL_RGBA, xx width, xx height, 0, GL_RGBA, GL_UNSIGNED_BYTE, data);

    return cast (TextureHandle) result;
}

BlitToTexture :: (texture : TextureHandle, x : s32, y : s32, width : u32, height : u32, data : *void)
{
    #import "GL";
    GL_Utils :: #import "GL_Utils";

    GL_Utils.StateBlock (GL_TEXTURE_BINDING_2D, (prev : GLuint) {glBindTexture (GL_TEXTURE_2D, prev);});

    glBindTexture (GL_TEXTURE_2D, texture);
    glTexSubImage2D (GL_TEXTURE_2D, 0, x, y, xx width, xx height, GL_RGBA, GL_UNSIGNED_BYTE, data);
}

#scope_module

UseTexture :: inline (texture : TextureHandle)
{
    #import "GL";
    GL_Utils :: #import "GL_Utils";

    glBindTexture (GL_TEXTURE_2D, texture);
}

#scope_export
