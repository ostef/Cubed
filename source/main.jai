Enable_Chunk_Bounds_Check :: true;

Basic :: #import "Basic" () (MEMORY_DEBUGGER = false);
using, only (.["+", "-", "*", "/"]) Basic;

#import "Common";
#import "Array";
#import "Hash_Map";
#import "SDL";
#import "GL";
GL_Utils :: #import "GL_Utils";
#import "Random64";

Threads :: #import "Thread";
System :: #import "System";

Im3d :: #import "Im3d";
Im3dImpl :: #import "Im3d/Impl/GL";
ImGui :: #import "ImGui";
ImGuiSDL :: #import "ImGui/Impl/SDL";
ImGuiGL :: #import "ImGui/Impl/GL";

Math :: #import "Math";
PI :: Math.PI;
Cos :: Math.cos;
Sin :: Math.sin;
Tan :: Math.tan;
Acos :: Math.acos;
Asin :: Math.asin;
Atan :: Math.atan;
Atan2 :: Math.atan2;
Sqrt :: Math.sqrt;
Floor :: Math.floor;
Ceil :: Math.ceil;

#load "linalg.jai";
#load "camera.jai";
#load "draw.jai";
#load "debug_draw.jai";
#load "physics.jai";
#load "noise.jai";
#load "world.jai";
#load "generation.jai";
#load "ui.jai";
#load "player.jai";
#load "biomes.jai";

g_window : *SDL_Window;
g_camera : Camera;
g_fps_camera := true;
g_mouse_delta : Vec2f;
g_should_capture_mouse := true;
g_settings : struct
{
    render_distance := 6;
}
g_world : World;
g_player : Player;
g_physics_breakpoint_hit : bool;
g_physics_step : bool;
g_prev_keyboard_state : [SDL_NUM_SCANCODES]bool;
g_prev_mouse_state : u32;

Fixed_Delta_Time :: 1 / 60.0;

PhysicsDebugBreak :: inline ()
{
    if !g_physics_breakpoint_hit
        Im3d.EndFrame ();

    g_physics_breakpoint_hit = true;
}

PhysicsIsRunning :: inline () -> bool
{
    return !g_physics_breakpoint_hit || g_physics_step;
}

PhysicsStep :: inline ()
{
    g_physics_step = true;
}

PhysicsResume :: inline ()
{
    g_physics_breakpoint_hit = false;
}

GetMousePosition :: inline (window : *SDL_Window = null) -> Vec2f #must
{
    window_x, window_y : s32;
    if window
        SDL_GetWindowPosition (window, *window_x, *window_y);

    mouse_x, mouse_y : s32;
    SDL_GetGlobalMouseState (*mouse_x, *mouse_y);

    mouse_x -= window_x;
    mouse_y -= window_y;

    return .{xx mouse_x, xx mouse_y};
}

IsKeyDown :: inline (key : SDL_Keycode) -> bool #must
{
    keyboard := SDL_GetKeyboardState (null);

    return xx keyboard[cast (s32) SDL_GetScancodeFromKey (key)];
}

IsKeyPressed :: inline (key : SDL_Keycode) -> bool #must
{
    return !g_prev_keyboard_state[cast (s32) SDL_GetScancodeFromKey (key)] && IsKeyDown (key);
}

IsKeyReleased :: inline (key : SDL_Keycode) -> bool #must
{
    return g_prev_keyboard_state[cast (s32) SDL_GetScancodeFromKey (key)] && !IsKeyDown (key);
}

IsMouseButtonDown :: inline (button : int) -> bool #must
{
    state := SDL_GetMouseState (null, null);

    return state & SDL_BUTTON (button) != 0;
}

IsMouseButtonPressed :: inline (button : int) -> bool #must
{
    return (g_prev_mouse_state & SDL_BUTTON (button)) == 0 && IsMouseButtonDown (button);
}

IsMouseButtonReleased :: inline (button : int) -> bool #must
{
    return (g_prev_mouse_state & SDL_BUTTON (button)) != 0 && !IsMouseButtonDown (button);
}

UpdateIm3dKeys :: ()
{
    app := Im3d.GetAppData ();
    app.keyDown[Im3d.Key.Mouse_Left] = IsMouseButtonDown (SDL_BUTTON_LEFT);

    app.keyDown[Im3d.Key.L] = IsKeyDown (SDLK_l);
    app.keyDown[Im3d.Key.T] = IsKeyDown (SDLK_t);
    app.keyDown[Im3d.Key.R] = IsKeyDown (SDLK_r);
    app.keyDown[Im3d.Key.S] = IsKeyDown (SDLK_s);

    if IsKeyDown (SDLK_LALT)
    {
        app.snapTranslation = 0.5;
        app.snapRotation    = ToRadians (30.0);
        app.snapScale       = 0.5;
    }
    else
    {
        app.snapTranslation = 0;
        app.snapRotation    = 0;
        app.snapScale       = 0;
    }
}

main :: ()
{
    #if Basic.MEMORY_DEBUGGER
    {
        defer {
            options : Basic.Leak_Report_Options;
            options.known_allocation_leaves = Common_Allocation_Leaves;
            Basic.report_memory_leaks (*options);
        }
    }

    #if OS == .WINDOWS
    {
        Winmm :: #system_library "Winmm";
        timeBeginPeriod :: (uPeriod : u32) -> u32 #foreign Winmm;
        timeBeginPeriod (1);
    }

    logger_data := ConsoleLogger.{ report_filenames = false };
    context.logger_data = *logger_data;
    context.logger = ConsoleLoggerProc;

    if SDL_Init (SDL_INIT_VIDEO) != 0
    {
        LogError ("Failed to initialize SDL: %", MakeString (SDL_GetError ()));
        return;
    }

    defer SDL_Quit ();

    // Multisampling params must be set before creating the window
    SDL_GL_SetAttribute (SDL_GL_MULTISAMPLEBUFFERS, 1);
    SDL_GL_SetAttribute (SDL_GL_MULTISAMPLESAMPLES, 4);

    x, y : s32 = SDL_WINDOWPOS_UNDEFINED;
    w, h : s32 = 1280, 720;
    g_window = SDL_CreateWindow ("Minecraft", x, y, w, h, SDL_WINDOW_OPENGL | SDL_WINDOW_RESIZABLE | SDL_WINDOW_SHOWN);
    if !g_window
    {
        LogError ("Could not create window: %", MakeString (SDL_GetError ()));
        return;
    }

    defer SDL_DestroyWindow (g_window);

    SDL_CaptureMouse (SDL_TRUE);

    SDL_GL_SetAttribute (SDL_GL_CONTEXT_PROFILE_MASK, xx SDL_GL_CONTEXT_PROFILE_CORE);

    gl_context := SDL_GL_CreateContext (g_window);
    if !gl_context
    {
        LogError ("Could not create OpenGL context: %", MakeString (SDL_GetError ()));
        return;
    }

    defer SDL_GL_DeleteContext (gl_context);

    gl_load (*gl, SDL_GL_GetProcAddress);

    LogMessage ("GL version: %", MakeString (glGetString (GL_VERSION)));

    if !DrawInit ("data/textures")
        return;

    ImGui.CreateContext ();
    defer ImGui.DestroyContext ();

    io := ImGui.GetIO ();
    io.ConfigFlags_ |= .NavEnableKeyboard;
    io.ConfigFlags_ |= .DockingEnable;
    io.ConfigFlags_ |= .ViewportsEnable;

    ImGui.StyleColorsDark ();
    {
        style := ImGui.GetStyle ();
        style.WindowRounding = 10;
        style.WindowTitleAlign = .{0.5, 0.5};
        style.ChildRounding = 3;
        style.FrameRounding = 6;
        style.PopupRounding = 3;
        style.GrabRounding = 4;
        style.TabRounding = 6;
        style.FramePadding = .{10, 6};
        style.SeparatorTextBorderSize = 1;
        style.FrameBorderSize = 1;
        style.ItemSpacing.y = 6;
        style.ItemInnerSpacing.x = 8;
        style.Colors[ImGui.Col.Border].w = 0.25;
    }

    io.Fonts.AddFontFromFileTTF (io.Fonts, "data/Roboto-Regular.ttf", 18);

    ImGuiSDL.Init (g_window, gl_context);
    defer ImGuiSDL.Terminate ();

    if !ImGuiGL.Init ()
    {
        LogError ("Could not initialize ImGui GL backend");
        return;
    }
    defer ImGuiGL.Terminate ();

    if !Im3dImpl.Init (g_window)
    {
        LogError ("Could not initialize Im3d");
        return;
    }

    a_aabb := AABB.{.{-1, -1, -1}, .{1, 1, 1}};
    b_aabb := AABB.{.{2, 2, 2}, .{3, 3, 3}};
    point := Vec3f.{-1, 0.5, 0.7};

    WorldInit (*g_world, 1725362821052241920);//Basic.current_time_monotonic ().low);
    defer WorldFree (*g_world);

    #if Basic.MEMORY_DEBUGGER
        Basic.allocations_before_this_call_will_not_be_considered_leaks ();

    g_camera.position.y = xx g_world.surface_params.water_level + 10.0;
    g_player.position.y = xx g_world.surface_params.water_level + 10.0;
    delta_time := Fixed_Delta_Time;
    quit := false;
    while !quit
    {
        defer ResetTemporaryStorage ();
        defer g_physics_step = false;

        frame_start := Basic.current_time_monotonic ();

        keyboard_state_len : s32;
        keyboard_state := SDL_GetKeyboardState (*keyboard_state_len);
        memcpy (g_prev_keyboard_state.data, keyboard_state, keyboard_state_len);

        g_prev_mouse_state = SDL_GetMouseState (null, null);

        g_mouse_delta = .{};
        event : SDL_Event;
        while SDL_PollEvent (*event)
        {
            ImGuiSDL.HandleWindowEvent (event);

            if event.type ==
            {
            case SDL_QUIT;
                quit = true;

            case SDL_KEYDOWN;
                if event.key.keysym.sym ==
                {
                case SDLK_F5;
                    PhysicsResume ();
                case SDLK_F10;
                    PhysicsStep ();
                }

            case SDL_MOUSEMOTION;
                g_mouse_delta.x = cast (float) event.motion.xrel;
                g_mouse_delta.y = cast (float) event.motion.yrel;

            case SDL_WINDOWEVENT;
                window := SDL_GetWindowFromID (event.window.windowID);
                if event.window.event == SDL_WINDOWEVENT_CLOSE && window == g_window
                    quit = true;
            }
        }

        if IsKeyPressed (SDLK_ESCAPE)
            g_should_capture_mouse = !g_should_capture_mouse;

        if g_should_capture_mouse
            SDL_SetRelativeMouseMode (SDL_TRUE);
        else
            SDL_SetRelativeMouseMode (SDL_FALSE);

        window_w, window_h : s32;
        SDL_GetWindowSize (g_window, *window_w, *window_h);

        ImGuiSDL.NewFrame ();
        ImGui.NewFrame ();

        if PhysicsIsRunning ()
            UpdateIm3dKeys ();

        Im3dImpl.NewFrame (
            g_camera.fov_in_degrees,
            ifx !ImGui.GetIO ().WantCaptureMouse && !g_should_capture_mouse && SDL_GetMouseFocus () == g_window
                then GetMousePosition (g_window)
                else .{-Math.FLOAT32_MAX, -Math.FLOAT32_MAX},
            g_camera.transform_matrix, g_camera.projection_matrix, delta_time
        );

        if PhysicsIsRunning ()
        {
            Im3d.NewFrame ();

            UpdatePlayer (*g_world, *g_player, delta_time, !ImGui.GetIO ().WantCaptureKeyboard);
        }

        if !g_physics_breakpoint_hit
        {
            if g_fps_camera
                UpdateFPSCamera (*g_camera, g_player, delta_time);
            else
                UpdateTPSCamera (*g_camera, g_player, delta_time);

            UpdateBlockBreaking (*g_world, *g_camera, *g_player);
        }
        else
        {
            UpdateFlyingCamera (*g_camera, delta_time, !ImGui.GetIO ().WantCaptureKeyboard);
        }

        // Update the Im3d matrices otherwise all drawn things will be delayed by one frame
        Im3dImpl.NewFrame (
            g_camera.fov_in_degrees,
            ifx !ImGui.GetIO ().WantCaptureMouse && !g_should_capture_mouse && SDL_GetMouseFocus () == g_window
                then GetMousePosition (g_window)
                else .{-Math.FLOAT32_MAX, -Math.FLOAT32_MAX},
            g_camera.transform_matrix, g_camera.projection_matrix, delta_time
        );

        // If we have a dockspace then ImGui will always ask to capture
        // the keyboard and we won't be able to move the camera
        // ImGui.DockSpaceOverViewport (null, .PassthruCentralNode);
        UIUpdate ();

        WorldHandleNewlyGeneratedChunks (*g_world);
        WorldGenerateAroundPosition (*g_world, g_camera.position, g_settings.render_distance);

        glViewport (0, 0, xx window_w, xx window_h);
        glClearColor (0.1, 0.1, 0.1, 1.0);
        glClear (GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

        DrawWorld (*g_world, *g_camera);
        if PhysicsIsRunning ()
            DrawPlayer (g_world, g_player, g_camera);

        if PhysicsIsRunning ()
            Im3d.EndFrame ();

        Im3dImpl.RenderDrawLists (Im3d.GetDrawLists (), Im3d.GetDrawListCount ());

        ImGui.Render ();
        ImGuiGL.RenderDrawData (ImGui.GetDrawData ());

        if io.ConfigFlags_ & .ViewportsEnable
        {
            backup_current_window := SDL_GL_GetCurrentWindow ();
            backup_current_context := SDL_GL_GetCurrentContext ();
            ImGui.UpdatePlatformWindows ();
            ImGui.RenderPlatformWindowsDefault ();
            SDL_GL_MakeCurrent (backup_current_window, backup_current_context);
        }

        SDL_GL_SwapWindow (g_window);

        Basic.sleep_milliseconds (10);

        frame_end := Basic.current_time_monotonic ();
        delta_time = cast (float) Basic.to_float64_seconds (frame_end - frame_start);
    }
}

#run {
    #import "Compiler";

    set_build_options_dc (.{output_executable_name="minecraft", output_path="../"});
}
