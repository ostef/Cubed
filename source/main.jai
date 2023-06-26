#import "Common";
#import "SDL";

g_window : *SDL_Window;

main :: ()
{
    context.logger = ConsoleLogger;

    if SDL_Init (SDL_INIT_VIDEO) != 0
    {
        LogError ("Failed to initialize SDL: %", MakeString (SDL_GetError ()));
        return;
    }

    defer SDL_Quit ();

    g_window = SDL_CreateWindow ("Minecraft", SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, 1280, 720, SDL_WINDOW_SHOWN);
    if !g_window
    {
        LogError ("Could not create window: %", MakeString (SDL_GetError ()));
        return;
    }

    defer SDL_DestroyWindow (g_window);

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
    }
}

#run {
    #import "Compiler";

    set_build_options_dc (.{output_executable_name="minecraft", output_path="../"});
}
