#import "Common";
#import "SDL";
#import "GL";

Math :: #import "Math";
PI :: Math.PI;
Cos :: Math.cos;
Sin :: Math.sin;
Tan :: Math.tan;
Acos :: Math.acos;
Asin :: Math.asin;
Atan :: Math.atan;
Atan2 :: Math.atan2;

#load "linalg.jai";
#load "camera.jai";
#load "debug_draw.jai";

g_window : *SDL_Window;
g_camera : Camera;
g_mouse_delta : Vec2f;

IsKeyDown :: inline (key : SDL_Keycode) -> bool #must
{
    keyboard := SDL_GetKeyboardState (null);

    return xx keyboard[cast (s32) SDL_GetScancodeFromKey (key)];
}

main :: ()
{
    context.logger = ConsoleLoggerProc;

    if SDL_Init (SDL_INIT_VIDEO) != 0
    {
        LogError ("Failed to initialize SDL: %", MakeString (SDL_GetError ()));
        return;
    }

    defer SDL_Quit ();

    x, y : s32 = SDL_WINDOWPOS_UNDEFINED;
    w, h : s32 = 1280, 720;
    g_window = SDL_CreateWindow ("Minecraft", x, y, w, h, SDL_WINDOW_OPENGL | SDL_WINDOW_RESIZABLE | SDL_WINDOW_SHOWN);
    if !g_window
    {
        LogError ("Could not create window: %", MakeString (SDL_GetError ()));
        return;
    }

    defer SDL_DestroyWindow (g_window);

    SDL_GL_SetAttribute (SDL_GL_CONTEXT_PROFILE_MASK, xx SDL_GL_CONTEXT_PROFILE_CORE);

    gl_context := SDL_GL_CreateContext (g_window);
    if !gl_context
    {
        LogError ("Could not create OpenGL context: %", MakeString (SDL_GetError ()));
        return;
    }

    gl_load (*gl, SDL_GL_GetProcAddress);

    LogMessage ("GL version: %", MakeString (glGetString (GL_VERSION)));

    SDL_CaptureMouse (SDL_TRUE);
    SDL_SetRelativeMouseMode (SDL_TRUE);

    quit := false;
    while !quit
    {
        ResetTemporaryStorage ();

        g_mouse_delta = .{};
        event : SDL_Event;
        while SDL_PollEvent (*event)
        {
            if event.type ==
            {
            case SDL_QUIT;
                quit = true;

            case SDL_MOUSEMOTION;
                g_mouse_delta.x = cast (float) event.motion.xrel;
                g_mouse_delta.y = cast (float) event.motion.yrel;
            }
        }

        window_w, window_h : s32;
        SDL_GetWindowSize (g_window, *window_w, *window_h);

        UpdateFlyingCamera (*g_camera, 1.0 / 60.0);

        glViewport (0, 0, xx window_w, xx window_h);
        glClearColor (0.1, 0.1, 0.1, 1.0);
        glClear (GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

        DebugDrawLine (.{}, .{1, 0, 0}, .{1, 0, 0, 1});
        DebugDrawLine (.{}, .{0, 1, 0}, .{0, 1, 0, 1});
        DebugDrawLine (.{}, .{0, 0, 1}, .{0, 0, 1, 1});
        DebugDrawWireframeAABB (.{-1, -1, -1}, .{1, 1, 1}, .{1, 0, 0, 1});

        DebugDrawFlush ();
        SDL_GL_SwapWindow (g_window);
    }
}

#run {
    #import "Compiler";

    set_build_options_dc (.{output_executable_name="minecraft", output_path="../"});
}
