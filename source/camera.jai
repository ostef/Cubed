Camera :: struct
{
    position : Vec3f;
    euler_angles : EulerAngles;
    rotation : Quatf;
    mouse_input : Vec2f;

    base_movement_speed := 10.0;
    rotation_speed := 0.2;
    rotation_smoothing := 0.3;

    fov_in_degrees := 60.0;
    z_near := 0.01;
    z_far := 500.0;
    transform_matrix : Mat4f;
    view_matrix : Mat4f;
    projection_matrix : Mat4f;
    view_projection_matrix : Mat4f;
}

Plane :: struct
{
    normal : Vec3f;
    distance : float;
}

Frustum :: struct
{
    far_face, near_face : Plane;
    left_face, right_face : Plane;
    top_face, bottom_face : Plane;

    #place far_face;
    planes : [6]Plane;
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
    projection_matrix = Mat4fPerspectiveProjection (fov_in_degrees, aspect, z_near, z_far);
    view_projection_matrix = projection_matrix * view_matrix;
}

MakePlane :: inline (origin : Vec3f, normal : Vec3f) -> Plane #must
{
    inv_len := 1 / Length (normal);

    return .{ normal * inv_len, Dot (normal, origin) * inv_len };
}

SignedDistanceToPlane :: inline (point : Vec3f, plane : Plane) -> float #must
{
    return Dot (plane.normal, point) - plane.distance;
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

MakeViewFrustum :: (using camera : Camera) -> Frustum #must
{
    w, h : s32;
    SDL_GetWindowSize (g_window, *w, *h);

    aspect_ratio := cast (float) w / cast (float) h;

    half_v_side := z_far * Tan (ToRadians (fov_in_degrees * 0.5));
    half_h_side := half_v_side * aspect_ratio;

    right   := RightVector (transform_matrix);
    up      := UpVector (transform_matrix);
    forward := ForwardVector (transform_matrix);

    using result : Frustum = ---;
    near_face   = MakePlane (position + z_near * forward, forward);
    far_face    = MakePlane (position + z_far * forward, -forward);

    far_center := z_far * forward;
    right_face  = MakePlane (position, Cross (far_center + right * half_h_side, up));
    left_face   = MakePlane (position, Cross (up, far_center - right * half_h_side));
    top_face    = MakePlane (position, Cross (right, far_center + up * half_v_side));
    bottom_face = MakePlane (position, Cross (far_center - up * half_v_side, right));

    return result;
}

AABBIsInFrustum :: inline (aabb : AABB, using frustum : Frustum) -> bool #must
{
    // for planes
    // {
    //     axis_vert : Vec3f = ---;
    //     if it.normal.x < 0
    //         axis_vert.x = aabb.min.x;
    //     else
    //         axis_vert.x = aabb.max.x;

    //     if it.normal.y < 0
    //         axis_vert.y = aabb.min.y;
    //     else
    //         axis_vert.y = aabb.max.y;

    //     if it.normal.z < 0
    //         axis_vert.z = aabb.min.z;
    //     else
    //         axis_vert.z = aabb.max.z;

    //     if Dot (it.normal, axis_vert) + it.distance < 0
    //         return false;
    // }

    // return true;
    return AABBIsInFrontOrOnPlane (aabb, left_face)
        && AABBIsInFrontOrOnPlane (aabb, right_face)
        && AABBIsInFrontOrOnPlane (aabb, top_face)
        && AABBIsInFrontOrOnPlane (aabb, bottom_face)
        && AABBIsInFrontOrOnPlane (aabb, near_face)
        && AABBIsInFrontOrOnPlane (aabb, far_face);
}

PointIsInFrustum :: inline (point : Vec3f, using frustum : Frustum) -> bool #must
{
    return SignedDistanceToPlane (point, left_face) >= 0
        && SignedDistanceToPlane (point, right_face) >= 0
        && SignedDistanceToPlane (point, top_face) >= 0
        && SignedDistanceToPlane (point, bottom_face) >= 0
        && SignedDistanceToPlane (point, near_face) >= 0
        && SignedDistanceToPlane (point, far_face) >= 0;
}

ChunkIsInFrustum :: inline (chunk : Chunk, frustum : Frustum) -> bool #must
{
    aabb : AABB = ---;
    aabb.min = .{xx (chunk.x * Chunk_Size), 0, xx (chunk.z * Chunk_Size)};
    aabb.max = aabb.min + .{xx Chunk_Size, xx Chunk_Height, xx Chunk_Size};

    return AABBIsInFrustum (aabb, frustum);
}
