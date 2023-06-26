#import "Common";
#import "SDL";
#import "GL";

#load "linalg.jai";

g_window : *SDL_Window;
g_player_aabb : AABB;

main :: ()
{
    context.logger = ConsoleLogger;

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

    quit := false;
    while !quit
    {
        ResetTemporaryStorage ();

        event : SDL_Event;
        while SDL_PollEvent (*event)
        {
            if event.type == SDL_QUIT
                quit = true;
        }

        w, h : s32;
        SDL_GetWindowSize (g_window, *w, *h);
        glViewport (0, 0, xx w, xx h);
        glClearColor (1.0, 0.1, 0.1, 1.0);
        glClear (GL_COLOR_BUFFER_BIT);

        SDL_GL_SwapWindow (g_window);
    }
}

#run {
    #import "Compiler";

    set_build_options_dc (.{output_executable_name="minecraft", output_path="../"});
}
