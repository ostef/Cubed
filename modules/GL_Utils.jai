#import "Common";
#import "GL";

CheckShader :: (handle : GLuint, desc : string, location := #caller_location) -> bool #must
{
    status, log_length : GLint;
    glGetShaderiv (handle, GL_COMPILE_STATUS, *status);
    glGetShaderiv (handle, GL_INFO_LOG_LENGTH, *log_length);

    if !status
    {
        if log_length > 1
        {
            buffer := Alloc (u8, log_length + 1, Temp);
            glGetShaderInfoLog (handle, xx log_length, null, buffer);
            LogError ("%:\n\n%", desc, MakeString (log_length, buffer), location = location);
        }
        else
            LogError (desc, location = location);
    }

    return status != 0;
}

CheckShaderProgram :: (handle : GLuint, desc : string, location := #caller_location) -> bool #must
{
    status, log_length : GLint;
    glGetProgramiv (handle, GL_LINK_STATUS, *status);
    glGetProgramiv (handle, GL_INFO_LOG_LENGTH, *log_length);

    if !status
    {
        if log_length > 1
        {
            buffer := Alloc (u8, log_length + 1, Temp);
            glGetProgramInfoLog (handle, xx log_length, null, buffer);
            LogError ("%:\n\n%", desc, MakeString (log_length, buffer), location = location);
        }
        else
            LogError (desc, location = location);
    }

    return status != 0;
}

CreateShaderProgram :: ($$vertex_source : string, $$fragment_source : string, $$geometry_source := "", location := #caller_location) -> GLuint #must
{
    prev_allocator := context.allocator;
    context.allocator = Temp;
    defer context.allocator = prev_allocator;

    state := GetTemporaryStorageState ();
    defer SetTemporaryStorageState (state);

    vertex_shader := glCreateShader (GL_VERTEX_SHADER);
    defer glDeleteShader (vertex_shader);

    #if is_constant (vertex_source)
        cstr_vertex_source := vertex_source.data;
    else
        cstr_vertex_source := StringCloneToCString (vertex_source);

    glShaderSource (vertex_shader, 1, *cstr_vertex_source, null);
    glCompileShader (vertex_shader);

    if !CheckShader (vertex_shader, "Could not compile vertex shader", location = location)
        return 0;

    geometry_shader : GLuint;
    defer glDeleteShader (geometry_shader);

    if geometry_source
    {
        geometry_shader = glCreateShader (GL_GEOMETRY_SHADER);

        #if is_constant (geometry_source)
            cstr_geometry_source := geometry_source.data;
        else
            cstr_geometry_source := StringCloneToCString (geometry_source);

        glShaderSource (geometry_shader, 1, *cstr_geometry_source, null);
        glCompileShader (geometry_shader);

        if !CheckShader (geometry_shader, "Could not compile geometry shader", location = location)
            return 0;
    }

    fragment_shader := glCreateShader (GL_FRAGMENT_SHADER);
    defer glDeleteShader (fragment_shader);

    #if is_constant (fragment_source)
        cstr_fragment_source := fragment_source.data;
    else
        cstr_fragment_source := StringCloneToCString (fragment_source);

    glShaderSource (fragment_shader, 1, *cstr_fragment_source, null);
    glCompileShader (fragment_shader);

    if !CheckShader (fragment_shader, "Could not compile vertex shader", location = location)
        return 0;

    shader_program := glCreateProgram ();

    glAttachShader (shader_program, vertex_shader);
    if geometry_shader
        glAttachShader (shader_program, geometry_shader);
    glAttachShader (shader_program, fragment_shader);
    glLinkProgram (shader_program);

    if !CheckShaderProgram (shader_program, "Could not link shader program", location = location)
    {
        glDeleteProgram (shader_program);

        return 0;
    }

    return shader_program;
}

EnableBlock :: (val : GLenum) #expand
{
    prev : GLboolean;
    glGetBooleanv (val, *prev);

    if !prev
        glEnable (val);

    `defer if !prev
        glDisable (val);
}

DisableBlock :: (val : GLenum) #expand
{
    prev : GLboolean;
    glGetBooleanv (val, *prev);

    if prev
        glDisable (val);

    `defer if prev
        glEnable (val);
}

StateBlock :: (val : GLenum, reset_func : (val : $T)) #expand
{
    prev_value : T;
    glGetIntegerv (val, cast (*GLint) *prev_value);
    `defer reset_func (prev_value);
}

StateBlock :: (val : GLenum, $N : int, reset_func : (vals : [N]$T)) #expand
{
    prev_values : [N]T;
    glGetIntegerv (val, cast (*GLint) prev_values.data);
    `defer reset_func (prev_values);
}

BlendFuncStateBlock :: () #expand
{
    prev_src_rgb, prev_src_a, prev_dst_rgb, prev_dst_a, prev_equ_rgb, prev_equ_a : GLint;
    glGetIntegerv (GL_BLEND_SRC_RGB, *prev_src_rgb);
    glGetIntegerv (GL_BLEND_SRC_ALPHA, *prev_src_a);
    glGetIntegerv (GL_BLEND_DST_RGB, *prev_dst_rgb);
    glGetIntegerv (GL_BLEND_DST_ALPHA, *prev_dst_a);
    glGetIntegerv (GL_BLEND_EQUATION_RGB, *prev_equ_rgb);
    glGetIntegerv (GL_BLEND_EQUATION_ALPHA, *prev_equ_a);
    `defer glBlendEquationSeparate (xx prev_equ_rgb, xx prev_equ_a);
    `defer glBlendFuncSeparate (xx prev_src_rgb, xx prev_dst_rgb, xx prev_src_a, xx prev_dst_a);
}
