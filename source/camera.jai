Camera :: struct
{
    position : Vec3f;
    euler_angles : EulerAngles;
    rotation : Quatf;
    mouse_input : Vec2f;

    base_movement_speed := 2.0;
    rotation_speed := 0.2;
    rotation_smoothing := 0.3;

    fov_in_degrees := 60.0;
    transform_matrix : Mat4f;
    view_matrix : Mat4f;
    projection_matrix : Mat4f;
    view_projection_matrix : Mat4f;
}

UpdateFlyingCamera :: (using cam : *Camera, delta_time : float, allow_movement : bool)
{
    defer CalculateCameraMatrices (cam);

    if (SDL_GetWindowFlags (g_window) & SDL_WINDOW_INPUT_FOCUS) == 0
        return;

    movement_input : Vec3f;
    if allow_movement
    {
        movement_input = Vec3f.{
            xx (cast (s32) IsKeyDown (SDLK_d) - cast (s32) IsKeyDown (SDLK_a)),
            xx (cast (s32) IsKeyDown (SDLK_SPACE) - cast (s32) IsKeyDown (SDLK_LCTRL)),
            xx (cast (s32) IsKeyDown (SDLK_w) - cast (s32) IsKeyDown (SDLK_s))
        };
        movement_input = Normalized (movement_input);
    }

    if IsKeyDown (SDLK_DOWN)
        base_movement_speed = Max (base_movement_speed * 0.9, 1);
    else if IsKeyDown (SDLK_UP)
        base_movement_speed = Min (base_movement_speed * 1.1, 50);
    speed := base_movement_speed;
    if IsKeyDown (SDLK_LSHIFT)
        speed *= 10;

    position += speed * delta_time * (
        RightVector (transform_matrix)   * movement_input.x +
        UpVector (transform_matrix)      * movement_input.y +
        ForwardVector (transform_matrix) * movement_input.z
    );

    mouse_delta := ifx g_should_capture_mouse then g_mouse_delta else .{};
    mouse_input = Lerp (mouse_input, mouse_delta, rotation_smoothing);
    rotation_delta := mouse_input * rotation_speed;
    euler_angles.yaw   += ToRadians (rotation_delta.x);
    euler_angles.pitch += ToRadians (rotation_delta.y);
    euler_angles.pitch = Clamp (euler_angles.pitch, ToRadians (-80.0), ToRadians (80.0));

    rotation = QuatfFromEulerAngles (euler_angles);
}

CalculateCameraMatrices :: inline (using cam : *Camera)
{
    transform_matrix = Mat4fTranslate (position) * Mat4fFromQuat (rotation);
    view_matrix = Inverse (transform_matrix);

    w, h : s32;
    SDL_GetWindowSize (g_window, *w, *h);

    aspect := cast (float) w / cast (float) h;
    projection_matrix = Mat4fPerspectiveProjection (fov_in_degrees, aspect, 0.01, 1000.0);
    view_projection_matrix = projection_matrix * view_matrix;
}
