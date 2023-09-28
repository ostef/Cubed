Camera :: struct
{
    position : Vec3f;
    target_euler_angles : EulerAngles;
    euler_angles : EulerAngles;
    rotation : Quatf;
    mouse_input : Vec2f;

    base_movement_speed := 1.0;
    rotation_speed := 50.0; // in degrees per second
    rotation_smoothing := 0.3;

    distance_to_target := 4.0;
    look_at_offset := Vec2f.{0, 1.5};

    fov_in_degrees := 60.0;
    z_near := 0.01;
    z_far := 500.0;
    transform_matrix : Mat4f;
    view_matrix : Mat4f;
    projection_matrix : Mat4f;
    view_projection_matrix : Mat4f;
}

First_Person_FOV :: 70.0;

Plane :: struct
{
    origin : Vec3f;
    normal : Vec3f;
}

Frustum :: struct
{
    far_plane, near_plane : Plane;
    left_plane, right_plane : Plane;
    top_plane, bottom_plane : Plane;

    #place far_plane;
    planes : [6]Plane;
}

UpdateFreeCamera :: (using cam : *Camera, delta_time : float, allow_movement : bool)
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
    rotation_delta := mouse_delta * rotation_speed * delta_time;

    target_euler_angles.pitch += ToRadians (rotation_delta.y);
    target_euler_angles.pitch = Clamp (target_euler_angles.pitch, ToRadians (-80.0), ToRadians (80.0));
    target_euler_angles.yaw   += ToRadians (rotation_delta.x);

    euler_angles.pitch = Lerp (euler_angles.pitch, target_euler_angles.pitch, rotation_smoothing);
    euler_angles.yaw = Lerp (euler_angles.yaw, target_euler_angles.yaw, rotation_smoothing);

    rotation = QuatfFromEulerAngles (euler_angles);
}

UpdateFirstPersonCamera :: (using camera : *Camera, player : Player, delta_time : float)
{
    defer CalculateCameraMatrices (camera);

    position = player.position + .{0, Player_Eyes_Height, 0};

    euler_angles.yaw = player.orientation;

    mouse_delta := ifx g_should_capture_mouse then g_mouse_delta else .{};
    rotation_delta := mouse_delta * Player_Rotation_Speed * Fixed_Delta_Time;

    target_euler_angles.pitch += ToRadians (rotation_delta.y);
    target_euler_angles.pitch = Clamp (target_euler_angles.pitch, ToRadians (-80.0), ToRadians (80.0));

    euler_angles.pitch = Lerp (euler_angles.pitch, target_euler_angles.pitch, Player_Rotation_Smoothing);
    euler_angles.yaw = player.orientation;

    target_euler_angles.yaw = euler_angles.yaw;

    rotation = QuatfFromEulerAngles (euler_angles);
}

UpdateThirdPersonCamera :: (using camera : *Camera, player : Player, delta_time : float, front := false)
{
    defer CalculateCameraMatrices (camera);

    mouse_delta := ifx g_should_capture_mouse then g_mouse_delta else .{};
    rotation_delta := mouse_delta * Player_Rotation_Speed * Fixed_Delta_Time;

    target_euler_angles.pitch += ToRadians (rotation_delta.y);
    target_euler_angles.pitch = Clamp (target_euler_angles.pitch, ToRadians (-80.0), ToRadians (80.0));

    euler_angles.pitch = Lerp (euler_angles.pitch, target_euler_angles.pitch, Player_Rotation_Smoothing);
    if front
        euler_angles.yaw = player.orientation + Pi;
    else
        euler_angles.yaw = player.orientation;

    target_euler_angles.yaw = euler_angles.yaw;

    rotation = QuatfFromEulerAngles (euler_angles);

    position = player.position + RightVector (rotation) * look_at_offset.x
        + .{0, look_at_offset.y, 0}
        - ForwardVector (rotation) * distance_to_target;
}

CalculateCameraMatrices :: inline (using cam : *Camera)
{
    transform_matrix = Mat4fTranslate (position) * Mat4fFromQuat (rotation);
    view_matrix = Inverse (transform_matrix);

    w, h : s32;
    SDL_GetWindowSize (g_window, *w, *h);

    aspect := cast (float) w / cast (float) h;
    projection_matrix = Mat4fPerspectiveProjection (fov_in_degrees, aspect, z_near, z_far);
    view_projection_matrix = projection_matrix * view_matrix;
}

MakePlane :: inline (origin : Vec3f, normal : Vec3f) -> Plane #must
{
    return .{ origin, Normalized (normal) };
}

SignedDistanceToPlane :: inline (point : Vec3f, plane : Plane) -> float #must
{
    return Dot (plane.normal, point) - Dot (plane.normal, plane.origin);
}

AABBIsInFrontOrOnPlane :: (aabb : AABB, plane : Plane) -> bool #must
{
    center := (aabb.max + aabb.min) * 0.5;
    half_extents := aabb.max - center;

    r := half_extents.x * Abs (plane.normal.x)
        + half_extents.y * Abs (plane.normal.y)
        + half_extents.z * Abs (plane.normal.z);

    dist_to_plane := SignedDistanceToPlane (center, plane);

    return dist_to_plane > 0 || Abs (dist_to_plane) <= r;
}

MakeViewFrustum :: (using camera : Camera, distance := -1.0) -> Frustum #must
{
    w, h : s32;
    SDL_GetWindowSize (g_window, *w, *h);

    if distance < 0
        distance = z_far;

    aspect_ratio :=  cast (float) w / cast (float) h;
    inv_aspect_ratio := cast (float) h / cast (float) w;

    half_near_v_side := z_near * Tan (ToRadians (fov_in_degrees * 0.5));
    half_near_h_side := half_near_v_side * aspect_ratio;
    half_near_h_hypothenuse := Sqrt (z_near * z_near + half_near_h_side * half_near_h_side);
    half_near_v_hypothenuse := Sqrt (z_near * z_near + half_near_v_side * half_near_v_side);

    half_far_v_side := distance * Tan (ToRadians (fov_in_degrees * 0.5));
    half_far_h_side := half_far_v_side * aspect_ratio;
    half_far_h_hypothenuse := Sqrt (distance * distance + half_far_h_side * half_far_h_side);
    half_far_v_hypothenuse := Sqrt (distance * distance + half_far_v_side * half_far_v_side);

    right   := RightVector (transform_matrix);
    up      := UpVector (transform_matrix);
    forward := ForwardVector (transform_matrix);

    using result : Frustum = ---;
    near_plane   = MakePlane (position + z_near * forward, forward);
    far_plane    = MakePlane (position + distance * forward, -forward);

    far_center := distance * forward;

    far_right := far_center + right * half_far_h_side;
    far_left  := far_center - right * half_far_h_side;
    right_center := far_right - Normalized (far_right) * (half_far_h_hypothenuse - half_near_h_hypothenuse) * 0.5;
    left_center  := far_left - Normalized (far_left) * (half_far_h_hypothenuse - half_near_h_hypothenuse) * 0.5;

    right_plane  = MakePlane (position + right_center, Cross (far_right, up));
    left_plane   = MakePlane (position + left_center, Cross (up, far_left));

    far_top    := far_center + up * half_far_v_side;
    far_bottom := far_center - up * half_far_v_side;
    top_center    := far_top - Normalized (far_top) * (half_far_v_hypothenuse - half_near_v_hypothenuse) * 0.5;
    bottom_center := far_bottom - Normalized (far_bottom) * (half_far_v_hypothenuse - half_near_v_hypothenuse) * 0.5;

    top_plane    = MakePlane (position + top_center, Cross (right, far_top));
    bottom_plane = MakePlane (position + bottom_center, Cross (far_bottom, right));

    return result;
}

AABBIsInFrustum :: inline (aabb : AABB, using frustum : Frustum) -> bool #must
{
    return AABBIsInFrontOrOnPlane (aabb, left_plane)
        && AABBIsInFrontOrOnPlane (aabb, right_plane)
        && AABBIsInFrontOrOnPlane (aabb, top_plane)
        && AABBIsInFrontOrOnPlane (aabb, bottom_plane)
        && AABBIsInFrontOrOnPlane (aabb, near_plane)
        && AABBIsInFrontOrOnPlane (aabb, far_plane);
}

PointIsInFrustum :: inline (point : Vec3f, using frustum : Frustum) -> bool #must
{
    return SignedDistanceToPlane (point, left_plane) >= 0
        && SignedDistanceToPlane (point, right_plane) >= 0
        && SignedDistanceToPlane (point, top_plane) >= 0
        && SignedDistanceToPlane (point, bottom_plane) >= 0
        && SignedDistanceToPlane (point, near_plane) >= 0
        && SignedDistanceToPlane (point, far_plane) >= 0;
}

ChunkIsInFrustum :: inline (chunk : Chunk, frustum : Frustum) -> bool #must
{
    return AABBIsInFrustum (ChunkAABB (chunk.x, chunk.z), frustum);
}
