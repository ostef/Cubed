Framebuffer :: struct
{
    handle : GLuint;
    color_texture, depth_stencil_renderbuffer : GLuint;

    width, height : s32;
}

CreateFramebuffer :: (fb : *Framebuffer, width : s32, height : s32) -> bool
{
    GL_Utils.StateBlock (GL_DRAW_FRAMEBUFFER_BINDING, (prev : GLuint) {glBindFramebuffer (GL_DRAW_FRAMEBUFFER, prev);});
    GL_Utils.StateBlock (GL_READ_FRAMEBUFFER_BINDING, (prev : GLuint) {glBindFramebuffer (GL_READ_FRAMEBUFFER, prev);});

    glGenFramebuffers (1, *fb.handle);
    glBindFramebuffer (GL_FRAMEBUFFER, fb.handle);

    {
        GL_Utils.StateBlock (GL_TEXTURE_BINDING_2D, (prev : GLuint) {glBindTexture (GL_TEXTURE_2D, prev);});

        glGenTextures (1, *fb.color_texture);
        glBindTexture (GL_TEXTURE_2D, fb.color_texture);
        glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexImage2D (GL_TEXTURE_2D, 0, GL_RGBA, xx width, xx height, 0, GL_RGBA, GL_UNSIGNED_BYTE, null);
    }

    {
        GL_Utils.StateBlock (GL_RENDERBUFFER_BINDING, (prev : GLuint) {glBindRenderbuffer (GL_RENDERBUFFER, prev);});

        glGenRenderbuffers (1, *fb.depth_stencil_renderbuffer);
        glBindRenderbuffer (GL_RENDERBUFFER, fb.depth_stencil_renderbuffer);
        glRenderbufferStorage (GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, xx width, xx height);
    }

    glFramebufferTexture2D (GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, fb.color_texture, 0);
    glFramebufferRenderbuffer (GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_RENDERBUFFER, fb.depth_stencil_renderbuffer);

    fb.width = width;
    fb.height = height;

    return glCheckFramebufferStatus (GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE;
}

DestroyFramebuffer :: inline (fb : *Framebuffer)
{
    glDeleteFramebuffers (1, *fb.handle);
    glDeleteTextures (1, *fb.color_texture);
    glDeleteRenderbuffers (1, *fb.depth_stencil_renderbuffer);
}

ResizeFramebuffer :: (fb : *Framebuffer, width : s32, height : s32)
{
    if width == fb.width && height == fb.height
        return;

    GL_Utils.StateBlock (GL_TEXTURE_BINDING_2D, (prev : GLuint) {glBindTexture (GL_TEXTURE_2D, prev);});
    GL_Utils.StateBlock (GL_RENDERBUFFER_BINDING, (prev : GLuint) {glBindRenderbuffer (GL_RENDERBUFFER, prev);});

    glBindTexture (GL_TEXTURE_2D, fb.color_texture);
    glTexImage2D (GL_TEXTURE_2D, 0, GL_RGBA, xx width, xx height, 0, GL_RGBA, GL_UNSIGNED_BYTE, null);

    glBindRenderbuffer (GL_RENDERBUFFER, fb.depth_stencil_renderbuffer);
    glRenderbufferStorage (GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, xx width, xx height);

    fb.width = width;
    fb.height = height;
}

UseFramebuffer :: inline (fb : *Framebuffer)
{
    if !fb
        glBindFramebuffer (GL_FRAMEBUFFER, 0);
    else
        glBindFramebuffer (GL_FRAMEBUFFER, fb.handle);
}

RenderFramebuffer :: inline (fb : Framebuffer)
{
    prev := Stylo.GetTexture ();
    defer Stylo.SetTexture (prev);

    Stylo.SetTexture (fb.color_texture);
    Stylo.PushRect (.{0,0}, .{xx fb.width, xx fb.height});
}
