#scope_file

g_gl_initialized : bool;
g_vao, g_vbo : u32;
g_shader : u32;

#scope_export

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

    glUseProgram (g_shader);

    view_projection_matrix := mat4f_orthographic_projection (0, xx width, 0, xx height, 0, 1);

    loc_view_proj := glGetUniformLocation (g_shader, "u_View_Projection_Matrix");
    glUniformMatrix4fv (loc_view_proj, 1, GL_TRUE, *view_projection_matrix.r0c0);

    loc_texture := glGetUniformLocation (g_shader, "u_Texture");
    glUniform1i (loc_texture, 0);

    loc_use_texture := glGetUniformLocation (g_shader, "u_Use_Texture");

    list := g_first_draw_list;
    while list
    {
        next := list.next;

        glBufferSubData (GL_ARRAY_BUFFER, 0, size_of (Vertex) * list.vertex_count, list.vertices.data);

        for cmd_i : 0..list.command_count - 1
        {
            cmd := list.commands[cmd_i];

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
