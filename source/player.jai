Player :: struct
{
    position : Vec3f;
    target_orientation : float;
    orientation : float;
    velocity : Vec3f;
    flying := true;
    enable_collisions := false;
    was_on_ground, is_on_ground : bool;
    fly_toggle_timer : float;

    transform_matrix : Mat4f;

    pose : SkeletonPose;
}

Player_Fly_Toggle_Timer := 0.5; // seconds
Player_Height :: 1.8;
Player_Size :: 0.7;
Player_Movement_Speed :: 1.0;
Player_Jump_Height :: 1.01;
Player_Rotation_Speed :: 60.0;  // in degrees per second
Player_Rotation_Smoothing :: 0.3;
Gravity :: 0.8;
Penetration_Threshold :: 0.001;
Ground_Test_Threshold :: 0.01;

CalculateJumpForce :: inline (jump_height : float, gravity : float) -> float #must
{
    return Sqrt (2 * gravity * jump_height);
}

PlayerAABB :: inline (using player : Player) -> AABB #must
{
    return MakeAABBPositionHalfSize (position + .{0, Player_Height * 0.5, 0}, Vec3f.{Player_Size, Player_Height, Player_Size} * 0.5);
}

g_player_movement_input : Vec3f;

UpdatePlayer :: (world : *World, using player : *Player, delta_time : float, allow_movement := true)
{
    if fly_toggle_timer < 0 || is_on_ground
        fly_toggle_timer = 0;
    else
        fly_toggle_timer -= delta_time;

    if !g_physics_breakpoint_hit
    {
        if allow_movement && (SDL_GetWindowFlags (g_window) & SDL_WINDOW_INPUT_FOCUS) != 0
        {
            g_player_movement_input.x = xx (cast (s32) IsKeyDown (SDLK_d) - cast (s32) IsKeyDown (SDLK_a));
            g_player_movement_input.z = xx (cast (s32) IsKeyDown (SDLK_w) - cast (s32) IsKeyDown (SDLK_s));
            if flying
                g_player_movement_input.y = xx (cast (s32) IsKeyDown (SDLK_SPACE) - cast (s32) IsKeyDown (SDLK_LCTRL));

            g_player_movement_input = Normalized (g_player_movement_input);
        }
        else
        {
            g_player_movement_input = .{};
        }
    }

    if !flying
        velocity.y -= Gravity * delta_time;

    if allow_movement && IsKeyPressed (SDLK_SPACE)
    {
        if fly_toggle_timer > 0
        {
            flying = !flying;
        }
        else
        {
            fly_toggle_timer = Player_Fly_Toggle_Timer;

            if !flying && is_on_ground
                velocity.y = CalculateJumpForce (Player_Jump_Height, Gravity * delta_time);
        }
    }

    movement_speed := Player_Movement_Speed;
    if IsKeyDown (SDLK_LSHIFT)
        movement_speed *= 10;
    movement_speed *= g_settings.player_speed_mult;
    movement_speed *= delta_time;

    if !flying
    {
        velocity = RightVector (transform_matrix) * g_player_movement_input.x * movement_speed
            + ForwardVector (transform_matrix) * g_player_movement_input.z * movement_speed
            + .{0, velocity.y, 0};
    }
    else
    {
        velocity = RightVector (transform_matrix) * g_player_movement_input.x * movement_speed
            + UpVector (transform_matrix) * g_player_movement_input.y * movement_speed
            + ForwardVector (transform_matrix) * g_player_movement_input.z * movement_speed;
    }

    if g_should_capture_mouse && allow_movement
        target_orientation += ToRadians (g_mouse_delta.x * Player_Rotation_Speed * delta_time);

    orientation = Lerp (orientation, target_orientation, Player_Rotation_Smoothing);

    // Because all collidable things are axis aligned boxes, the wall sliding
    // is limited to 3-axes, meaning we do not need to do more than 3 iterations
    // of collision resolution. If we have less than 3 iterations, we'll be able
    // to go through blocks when sliding along walls
    if enable_collisions
    {
        for 1..3
        {
            player_aabb := PlayerAABB (player);
            velocity_dir, velocity_len := Normalized (velocity);
            hit_result := SweptAABBIntersectsWorld (world, player_aabb, velocity_dir, velocity_len);

            if hit_result.hit
            {
                intermediate_velocity := velocity_dir * (hit_result.distance - Penetration_Threshold);
                position += intermediate_velocity;
                velocity -= intermediate_velocity;
                sliding_velocity := hit_result.normal * Dot (velocity, hit_result.normal);
                velocity -= sliding_velocity;
            }
        }
    }

    position += velocity;

    was_on_ground = is_on_ground;
    is_on_ground = false;
    {
        player_aabb := PlayerAABB (player);
        ground_test := SweptAABBIntersectsWorld (world, player_aabb, .{0, -1, 0}, Ground_Test_Threshold);
        if ground_test.hit && ground_test.block_face == .Above
            is_on_ground = true;
    }

    transform_matrix = Mat4fTranslate (position) * Mat4fRotate (.{0, 1, 0}, orientation);
}

Block_Selection_Distance :: 4.0;

UpdateBlockBreaking :: (world : *World, using camera : *Camera, player : *Player)
{
    hit_result := RayIntersectsWorld (
        world,
        .{
            origin=camera.position + ForwardVector (transform_matrix) * Player_Size,
            direction=ForwardVector (transform_matrix),
            length=Block_Selection_Distance
        }
    );

    if hit_result.hit
    {
        block_aabb := BlockAABB (hit_result.block_x, hit_result.block_y, hit_result.block_z);
        Im3d.DrawAlignedBox (block_aabb.min, block_aabb.max);

        if !ImGui.GetIO ().WantCaptureMouse && (SDL_GetWindowFlags (g_window) & SDL_WINDOW_INPUT_FOCUS) != 0 && IsMouseButtonPressed (SDL_BUTTON_LEFT)
        {
            block_x, block_z := ChunkAbsoluteToRelativeCoordinates (hit_result.chunk.x, hit_result.chunk.z, hit_result.block_x, hit_result.block_z);
            ChunkSetBlockInChunk (hit_result.chunk, block_x, hit_result.block_y, block_z, .{});
        }
    }
}

DrawPlayer :: (world : World, using player : Player, camera : Camera)
{
    if !pose.skeleton
    {
        InitSkeletonPose (*pose, *g_steve_mesh.skeleton, init_gl_objects = true);
    }

    // aabb := PlayerAABB (player);
    // Im3d.DrawAlignedBox (aabb.min, aabb.max);
    // Im3d.DrawArrow (position, position + velocity * 60);
    GL_Utils.StateBlock (GL_ACTIVE_TEXTURE, (prev : GLenum) {glActiveTexture (prev);});
    GL_Utils.StateBlock (GL_TEXTURE_BINDING_2D_ARRAY, (prev : GLuint) {glBindTexture (GL_TEXTURE_2D_ARRAY, prev);});

    glActiveTexture (GL_TEXTURE0);
    glBindTexture (GL_TEXTURE_2D, g_steve_texture);

    time := cast (float) Basic.to_float64_seconds (Basic.current_time_monotonic ());
    time *= 5;
    // SampleAnimation (g_sprint_anim, time * 2, *pose);

    left_arm := HashMapGet (*pose.skeleton.name_to_joint_id, "Arm.L", -1);
    if left_arm >= 0
        pose.joints[left_arm].local_orientation = QuatfFromAxisAngle (.{1,0,0}, Cos (time) + Pi);

    right_arm := HashMapGet (*pose.skeleton.name_to_joint_id, "Arm.R", -1);
    if right_arm >= 0
        pose.joints[right_arm].local_orientation = QuatfFromAxisAngle (.{-1,0,0}, Cos (time) + Pi);

    right_leg := HashMapGet (*pose.skeleton.name_to_joint_id, "Leg.R", -1);
    if right_leg >= 0
        pose.joints[right_leg].local_orientation = QuatfFromAxisAngle (.{1,0,0}, Cos (time) + Pi * 0.5);

    left_leg := HashMapGet (*pose.skeleton.name_to_joint_id, "Leg.L", -1);
    if left_leg >= 0
        pose.joints[left_leg].local_orientation = QuatfFromAxisAngle (.{-1,0,0}, Cos (time) + Pi * 1.5);

    CalculatePoseTransforms (*pose);
    GenerateSkinningMatrices (*pose, true);

    DebugDrawSkeletonPose (pose, transform_matrix, .{1,1,1,1});
    DrawSkinnedMesh (g_steve_mesh, pose, g_camera, transform_matrix);
}
