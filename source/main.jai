Basic :: #import "Basic";
using, only (.["+", "-", "*", "/"]) Basic;

#import "Common";
#import "SDL";
#import "GL";
GL_Utils :: #import "GL_Utils";
#import "Random64";

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
Floor :: Math.floor;
Ceil :: Math.ceil;

#load "linalg.jai";
#load "camera.jai";
#load "debug_draw.jai";
#load "physics.jai";
#load "noise.jai";

g_window : *SDL_Window;
g_camera : Camera;
g_mouse_delta : Vec2f;
g_should_capture_mouse : bool;

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

IsMouseButtonDown :: inline (button : int) -> bool #must
{
    state := SDL_GetMouseState (null, null);

    return state & SDL_BUTTON (button) != 0;
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
        // style.SeparatorTextBorderSize = 1;
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

    g_camera.position.z = -10;
    delta_time := 1 / 60.0;
    quit := false;
    while !quit
    {
        frame_start := Basic.current_time_monotonic ();

        ResetTemporaryStorage ();

        g_mouse_delta = .{};
        event : SDL_Event;
        while SDL_PollEvent (*event)
        {
            ImGuiSDL.HandleWindowEvent (event);

            if event.type ==
            {
            case SDL_QUIT;
                quit = true;

            case SDL_MOUSEMOTION;
                g_mouse_delta.x = cast (float) event.motion.xrel;
                g_mouse_delta.y = cast (float) event.motion.yrel;
            }
        }

        if !ImGui.GetIO ().WantCaptureMouse && IsMouseButtonDown (SDL_BUTTON_RIGHT)
        {
            g_should_capture_mouse = true;
            SDL_SetRelativeMouseMode (SDL_TRUE);
        }
        else
        {
            g_should_capture_mouse = false;
            SDL_SetRelativeMouseMode (SDL_FALSE);
        }

        window_w, window_h : s32;
        SDL_GetWindowSize (g_window, *window_w, *window_h);

        UpdateFlyingCamera (*g_camera, delta_time, !ImGui.GetIO ().WantCaptureKeyboard);

        ImGuiSDL.NewFrame ();
        ImGui.NewFrame ();

        ImGui.ShowDemoWindow ();

        UpdateIm3dKeys ();

        Im3dImpl.NewFrame (
            g_camera.fov_in_degrees,
            ifx !ImGui.GetIO ().WantCaptureMouse && !g_should_capture_mouse && SDL_GetMouseFocus () == g_window
                then GetMousePosition (g_window)
                else .{-Math.FLOAT32_MAX, -Math.FLOAT32_MAX},
            g_camera.transform_matrix, g_camera.projection_matrix, delta_time);
        Im3d.NewFrame ();

        Im3d.GizmoTranslation ("Point", *point.n);

        a_center := AABBCenter (a_aabb);
        Im3d.GizmoTranslation ("A_Center", *a_center.n);
        a_aabb = MakeAABBPositionHalfSize (a_center, AABBHalfSize (a_aabb));

        b_center := AABBCenter (b_aabb);
        Im3d.GizmoTranslation ("B_Center", *b_center.n);
        b_aabb = MakeAABBPositionHalfSize (b_center, AABBHalfSize (b_aabb));

        Im3d.DrawPoint (.{}, 10, Im3d.Color_White);
        Im3d.DrawXyzAxes ();

        if AABBIntersectsAABB (a_aabb, b_aabb)
            Im3d.PushColor (Im3d.Color_Red);
        else
            Im3d.PushColor (Im3d.Color_Green);

        Im3d.DrawAlignedBox (a_aabb.min, a_aabb.max);
        Im3d.DrawAlignedBox (b_aabb.min, b_aabb.max);

        Im3d.PushColor (Im3d.Color_White);
        Im3d.DrawAlignedBox (b_aabb.min - AABBHalfSize (a_aabb), b_aabb.max + AABBHalfSize (a_aabb));
        Im3d.PopColor ();

        Im3d.DrawPoint (point, 15, Im3d.Color_White);

        Im3d.DrawLine (AABBCenter (a_aabb), point, 1, Im3d.Color_White);

        hit_result := SweptAABBIntersectsAABB (a_aabb, b_aabb, Normalized (point - AABBCenter (a_aabb)), Length (point - AABBCenter (a_aabb)));
        if hit_result.hit
        {
            Im3d.DrawPoint (hit_result.position, 20, Im3d.Color_Red);
        }

        Im3d.PopColor ();

        Im3d.EndFrame ();

        ImGui.Render ();

        glViewport (0, 0, xx window_w, xx window_h);
        glClearColor (0.1, 0.1, 0.1, 1.0);
        glClear (GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

        Im3dImpl.RenderDrawLists (Im3d.GetDrawLists (), Im3d.GetDrawListCount ());

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

        frame_end := Basic.current_time_monotonic ();
        delta_time = cast (float) Basic.to_float64_seconds (frame_end - frame_start);
    }
}

#run {
    #import "Compiler";

    set_build_options_dc (.{output_executable_name="minecraft", output_path="../"});
}
