#import "Linalg";
#import "Math";
#import "SDL";

ImplData :: struct
{
    window : *SDL_Window;
    view_projection_matrix : Mat4f;
    projection_matrix : Mat4f;
    using renderer_data : RendererData;
}

GetData :: inline () -> *ImplData #must
{
    return cast (*ImplData) Im3d.GetAppData ().appData;
}

GetRendererData :: inline () -> *RendererData #must
{
    return *GetData ().renderer_data;
}

Init :: (window : *SDL_Window) -> bool
{
    data := Alloc (ImplData);
    data.window = window;
    Im3d.GetAppData ().appData = data;

    return InitRendererData ();
}

Terminate :: ()
{
    CleanupRendererData ();
    Free (Im3d.GetAppData ().appData);
    Im3d.GetAppData ().appData = null;
}

NewFrame :: (fov : float, camera_transform : Mat4f, projection : Mat4f, delta_time : float, use_orthographic_projection := false)
{
    app := Im3d.GetAppData ();
    data := GetData ();
    view_matrix := inverse (camera_transform);
    data.view_projection_matrix = projection * view_matrix;

    app.deltaTime = delta_time;

    width, height : s32;
    SDL_GetWindowSize (data.window, *width, *height);
    app.viewportSize.x = xx width;
    app.viewportSize.y = xx height;

    app.viewOrigin = translation_vector (camera_transform);
    app.viewDirection = forward_vector (camera_transform);
    app.projOrtho = use_orthographic_projection;

    window_x, window_y : s32;
    SDL_GetWindowPosition (data.window, *window_x, *window_y);

    mouse_x, mouse_y : s32;
    SDL_GetGlobalMouseState (*mouse_x, *mouse_y);

    mouse_x -= window_x;
    mouse_y -= window_y;

    cursor_pos := Vec2f.{
        mouse_x / app.viewportSize.x - 0.5,
        -(mouse_y / app.viewportSize.y - 0.5)
    };

    if app.projOrtho
    {
        app.projScaleY = 2 / projection.r1c1;

        app.cursorRayOrigin.x = cursor_pos.x / projection.r0c0;
        app.cursorRayOrigin.y = cursor_pos.y / projection.r1c1;
        app.cursorRayOrigin.z = 0;
        app.cursorRayOrigin = transform_point (camera_transform, app.cursorRayOrigin);

        app.cursorRayDirection = app.viewDirection;
    }
    else
    {
        app.projScaleY = 2 * tan (fov * PI / 180.0 * 0.5);

        app.cursorRayOrigin = app.viewOrigin;

        app.cursorRayDirection.x = cursor_pos.x / projection.r0c0;
        app.cursorRayDirection.y = cursor_pos.y / projection.r1c1;
        app.cursorRayDirection.z = 1;
        app.cursorRayDirection = transform_vector (camera_transform, normalized (app.cursorRayDirection));
    }

    Im3d.AppData.setCullFrustum (app, data.view_projection_matrix, true);
}
