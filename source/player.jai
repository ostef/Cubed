Player :: struct
{
    position : Vec3f;
    orientation : float;
    velocity : Vec3f;
    flying := true;
    transform_matrix : Mat4f;
    hit_result : HitResult;
}

Player_Height :: 1.8;
Player_Size :: 0.7;
Player_Movement_Speed :: 0.1;
Player_Jump_Height :: 1.0;
Player_Rotation_Speed :: 0.2;
Gravity :: 1.0;
Penetration_Threshold :: 0.01;

PlayerAABB :: inline (using player : Player) -> AABB #must
{
    return MakeAABBPositionHalfSize (position + .{0, Player_Height * 0.5, 0}, Vec3f.{Player_Size, Player_Height, Player_Size} * 0.5);
}

UpdatePlayer :: (world : *World, using player : *Player, delta_time : float, allow_movement := true)
{
    movement_input : Vec3f;
    if allow_movement && (SDL_GetWindowFlags (g_window) & SDL_WINDOW_INPUT_FOCUS) != 0
    {
        movement_input.x = xx (cast (s32) IsKeyDown (SDLK_d) - cast (s32) IsKeyDown (SDLK_a));
        movement_input.z = xx (cast (s32) IsKeyDown (SDLK_w) - cast (s32) IsKeyDown (SDLK_s));
        if flying
            movement_input.y = xx (cast (s32) IsKeyDown (SDLK_SPACE) - cast (s32) IsKeyDown (SDLK_LCTRL));

        movement_input = Normalized (movement_input);
    }

    movement_speed := Player_Movement_Speed;
    if IsKeyDown (SDLK_LSHIFT)
        movement_speed *= 10;

    if !flying
    {
        velocity.y -= Gravity;
        velocity = RightVector (transform_matrix) * movement_input.x * movement_speed
            + ForwardVector (transform_matrix) * movement_input.z * movement_speed
            + .{0, velocity.y, 0};
    }
    else
    {
        velocity = RightVector (transform_matrix) * movement_input.x * movement_speed
            + UpVector (transform_matrix) * movement_input.y * movement_speed
            + ForwardVector (transform_matrix) * movement_input.z * movement_speed;
    }

    if g_should_capture_mouse
        orientation += ToRadians (g_mouse_delta.x * Player_Rotation_Speed);

    // Because all collidable things are axis aligned boxes, the wall sliding
    // is limited to 3-axes, meaning we do not need to do more than 3 iterations
    // of collision resolution
    for 1..3
    {
        player_aabb := PlayerAABB (player);
        velocity_dir, velocity_len := Normalized (velocity);
        hit_result = SweptAABBIntersectsWorld (world, player_aabb, velocity_dir, velocity_len);

        if hit_result.hit
        {
            // new_dist := Distance (AABBCenter (player_aabb), hit_result.position);
            // Assert (Abs (new_dist - hit_result.distance) < 0.0001, "% %", new_dist, hit_result.distance);
            // stopped_velocity := velocity_dir * hit_result.distance;
            // new_position := position + velocity - hit_result.normal * Dot (velocity, hit_result.normal);
            // position = hit_result.position - .{0, Player_Height * 0.5, 0};
            // velocity = new_position - position;
            velocity -= hit_result.normal * Dot (velocity, hit_result.normal);
            // velocity = .{};
        }
        else
        {
            break;
        }
    }

    position += velocity;

    transform_matrix = Mat4fTranslate (position) * Mat4fRotate (.{0, 1, 0}, orientation);
}

DrawPlayer :: (world : World, using player : Player, camera : Camera)
{
    aabb := PlayerAABB (player);
    Im3d.DrawAlignedBox (aabb.min, aabb.max);
    Im3d.DrawArrow (position, position + velocity);
}
