#scope_module

Win32 :: #import "Win32";

Opengl32 :: #system_library "Opengl32";

wglCreateContext :: (hdc : Win32.HDC) -> Win32.HGLRC #foreign Opengl32;
wglDeleteContext :: (hglrc : Win32.HGLRC) -> Win32.BOOL #foreign Opengl32;
wglMakeCurrent :: (hdc : Win32.HDC, hglrc : Win32.HGLRC) -> Win32.BOOL #foreign Opengl32;
wglGetCurrentContext :: () -> Win32.HGLRC #foreign Opengl32;
wglGetCurrentDC :: () -> Win32.HDC #foreign Opengl32;
wglGetProcAddress :: (procname : *u8) -> *void #foreign Opengl32;
wglShareLists :: (hglrc1 : Win32.HGLRC, hglrc2 : Win32.HGLRC) -> Win32.BOOL #foreign Opengl32;

#scope_export

// @Todo: choose OpenGL version
// @Todo: multisampling
// @Todo: share lists

GLContext :: Win32.HGLRC;

GetProcAddress :: wglGetProcAddress;

CreateContext :: inline (window : *Window) -> GLContext #must #no_context
{
    hdc := Win32.GetDC (window.hwnd);
    pfd : Win32.PIXELFORMATDESCRIPTOR;
    pfd.nSize = size_of (Win32.PIXELFORMATDESCRIPTOR);
    pfd.nVersion = 1;
    pfd.dwFlags = Win32.PFD_DRAW_TO_WINDOW | Win32.PFD_SUPPORT_OPENGL | Win32.PFD_DOUBLEBUFFER;
    pfd.iPixelType = Win32.PFD_TYPE_RGBA;
    pfd.cColorBits = 32;
    pfd.cDepthBits = 24;
    pfd.cStencilBits = 8;

    pixel_format := Win32.ChoosePixelFormat (hdc, *pfd);
    Win32.SetPixelFormat (hdc, pixel_format, *pfd);

    return wglCreateContext (hdc);
}

DestroyContext :: inline (ctx : GLContext) #no_context
{
    wglDeleteContext (ctx);
}

MakeCurrent :: inline (window : *Window, ctx : GLContext) #no_context
{
    hdc := Win32.GetDC (window.hwnd);
    wglMakeCurrent (hdc, ctx);
}

SetSwapInterval :: inline (interval : int)
{
    // @Todo
}

ShareContexts :: inline (first : GLContext, second : GLContext) -> bool #no_context
{
    return xx wglShareLists (first, second);
}

GetCurrentContext :: inline () -> GLContext #must #no_context
{
    return wglGetCurrentContext ();
}

GetCurrentWindow :: inline () -> *Window #must, non_fenetres_window : bool #no_context
{
    hdc := wglGetCurrentDC ();
    if !hdc
        return null, false;

    hwnd := Win32.WindowFromDC (hdc);
    if !hwnd
        return null, false;

    window := GetWindowFromPlatformHandle (hwnd);
    if !window
        return null, true;

    return window, false;
}
