Player :: struct
{
    position : Vec3f;
    target_orientation : float;
    orientation : float;
    velocity : Vec3f;
    is_flying := false;
    enable_collisions := true;
    was_on_ground, is_on_ground : bool;
    fly_toggle_timer : float;
    movement_input : Vec3f;
    is_in_water : bool;
    is_underwater : bool;

    transform_matrix : Mat4f;

    anim_base_fsm : AnimationStateMachine;
    anim_data : PlayerAnimationData;
}

PlayerAnimationData :: struct
{
    is_on_ground : bool;
    is_flying : bool;
    is_falling : bool;
    is_underwater : bool;
    smooth_movement_input : Vec3f;
}

Player_Fly_Toggle_Timer := 0.5; // seconds
Player_Height :: 1.8;
Player_Size :: 0.7;
Player_Movement_Speed :: 5.0;
Player_Jump_Height :: 1.05;
Player_Rotation_Speed :: 60.0;  // in degrees per second
Player_Rotation_Smoothing :: 0.3;
Gravity :: 0.5;
Water_Drag :: 0.7;
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

InitPlayer :: (world : *World, using player : *Player)
{
    InitAnimationStateMachine (*anim_base_fsm, *GetMesh (.Human).skeleton);
    anim_base_fsm.user_data = *anim_data;
    AddAnimationState (*anim_base_fsm, "Grounded", PlayerGroundedAnimState);
    AddAnimationState (*anim_base_fsm, "Airborne", PlayerAirborneAnimState);
    AddAnimationState (*anim_base_fsm, "Flying", PlayerFlyingAnimState);
    AddAnimationState (*anim_base_fsm, "Underwater", PlayerUnderwaterAnimState);

    TransitionToState (*anim_base_fsm, "Grounded");
}

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
            movement_input.x = xx (cast (s32) IsKeyDown (SDLK_d) - cast (s32) IsKeyDown (SDLK_a));
            movement_input.z = xx (cast (s32) IsKeyDown (SDLK_w) - cast (s32) IsKeyDown (SDLK_s));
            if is_flying
                movement_input.y = xx (cast (s32) IsKeyDown (SDLK_SPACE) - cast (s32) IsKeyDown (SDLK_LCTRL));

            movement_input = Normalized (movement_input);
        }
        else
        {
            movement_input = .{};
        }
    }

    if !is_flying
    {
        velocity.y -= Gravity * Fixed_Delta_Time;
    }

    if allow_movement && IsKeyPressed (SDLK_SPACE)
    {
        if fly_toggle_timer > 0
        {
            is_flying = !is_flying;
        }
        else
        {
            fly_toggle_timer = Player_Fly_Toggle_Timer;

            // Jump!
            if !is_flying && is_on_ground && !is_in_water
                velocity.y = CalculateJumpForce (Player_Jump_Height, Gravity * Fixed_Delta_Time);
        }
    }

    if allow_movement && !is_flying && is_underwater && IsKeyDown (SDLK_SPACE)
    {
        velocity.y = CalculateJumpForce (Player_Jump_Height, Gravity * Fixed_Delta_Time);
    }

    movement_speed := Player_Movement_Speed;
    if is_flying && IsKeyDown (SDLK_LSHIFT)
        movement_speed *= 5;
    movement_speed *= g_settings.player_speed_mult;
    movement_speed *= Fixed_Delta_Time;

    if !is_flying
    {
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

    if !is_flying && is_in_water
        velocity *= Water_Drag;

    if g_should_capture_mouse && allow_movement
        target_orientation += ToRadians (g_mouse_delta.x * Player_Rotation_Speed * Fixed_Delta_Time);

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

    player_aabb := PlayerAABB (player);

    was_on_ground = is_on_ground;
    is_on_ground = false;

    ground_test := SweptAABBIntersectsWorld (world, player_aabb, .{0, -1, 0}, Ground_Test_Threshold);
    if ground_test.hit && ground_test.block_face == .Above
        is_on_ground = true;

    is_in_water = AABBIntersectsWorld (world, player_aabb, MakeBlockFlags (.Water));

    submerged_aabb := player_aabb;
    submerged_aabb.min.y += 0.5;
    is_underwater = AABBIntersectsWorld (world, submerged_aabb, MakeBlockFlags (.Water));

    anim_data.is_on_ground = is_on_ground;
    anim_data.is_flying = is_flying;
    anim_data.is_falling = velocity.y < 0 && !is_on_ground;
    anim_data.is_underwater = is_underwater;
    anim_data.smooth_movement_input = Linalg.lerp (anim_data.smooth_movement_input, movement_input, 0.3);

    transform_matrix = Mat4fTranslate (position) * Mat4fRotate (.{0, 1, 0}, orientation);
}

Block_Selection_Distance :: 4.0;

UpdateBlockSelectionAndDestruction :: (world : *World, using camera : *Camera, player : *Player)
{
    filter := Block_Flags_Solid;
    SetBlockFlag (*filter, .Grass_Foliage);

    hit_result := RayIntersectsWorld (
        world,
        .{
            origin=player.position + .{0, 1.5, 0} + ForwardVector (transform_matrix) * Player_Size,
            direction=ForwardVector (transform_matrix),
            length=Block_Selection_Distance
        },
        filter
    );

    if hit_result.hit
    {
        block_aabb := BlockAABB (hit_result.block_x, hit_result.block_y, hit_result.block_z);
        Im3d.DrawAlignedBox (block_aabb.min, block_aabb.max);

        if !ImGui.GetIO ().WantCaptureMouse && (SDL_GetWindowFlags (g_window) & SDL_WINDOW_INPUT_FOCUS) != 0 && IsMouseButtonDown (SDL_BUTTON_LEFT)
        {
            WorldDestroyBlock (world, hit_result.block_x, hit_result.block_y, hit_result.block_z);
        }
    }
}

UpdatePlayerAnimations :: (using player : *Player, delta_time : float)
{
    time := cast (float) Basic.to_float64_seconds (Basic.current_time_monotonic ()) * 30;

    breathing_additive_pose, rest_pose : SkeletonPose;
    InitSkeletonPose (*breathing_additive_pose, anim_base_fsm.final_pose.skeleton, allocator = Temp);
    InitSkeletonPose (*rest_pose, anim_base_fsm.final_pose.skeleton, allocator = Temp);

    SampleAnimation (GetAnimation (.Human_Breathing_Additive), time, *breathing_additive_pose);

    SubtractPoses (*breathing_additive_pose, rest_pose);

    UpdateAnimationStateMachine (*anim_base_fsm, delta_time);

    AddPoses (*anim_base_fsm.final_pose, breathing_additive_pose);

    GenerateSkinningMatrices (*anim_base_fsm.final_pose, true);
}

DrawPlayer :: (world : World, using player : Player, camera : Camera)
{
    if g_camera_mode == .First_Person
        return;

    // aabb := PlayerAABB (player);
    // Im3d.DrawAlignedBox (aabb.min, aabb.max);
    // Im3d.DrawArrow (position, position + velocity * 60);

    GL_Utils.StateBlock (GL_ACTIVE_TEXTURE, (prev : GLenum) {glActiveTexture (prev);});
    GL_Utils.StateBlock (GL_TEXTURE_BINDING_2D_ARRAY, (prev : GLuint) {glBindTexture (GL_TEXTURE_2D_ARRAY, prev);});

    glActiveTexture (GL_TEXTURE0);
    glBindTexture (GL_TEXTURE_2D, g_steve_texture);

    if g_settings.show_skeletons
        DebugDrawSkeletonPose (anim_base_fsm.final_pose, transform_matrix, .{1,1,1,1});
    DrawSkinnedMesh (GetMesh (.Human), anim_base_fsm.final_pose, camera, transform_matrix);
}

PlayerGroundedAnimState :: (machine : *AnimationStateMachine, using state : *AnimationState)
{
    using data := cast (*PlayerAnimationData) machine.user_data;
    if !is_on_ground
        TransitionToState (machine, "Airborne");
    if is_flying
        TransitionToState (machine, "Flying");

    left_pose, right_pose, fleft_pose, fright_pose, bleft_pose, bright_pose, forward_pose, backward_pose, idle_pose : SkeletonPose;
    InitSkeletonPose (*left_pose, state_pose.skeleton, allocator = Temp);
    InitSkeletonPose (*right_pose, state_pose.skeleton, allocator = Temp);
    InitSkeletonPose (*fleft_pose, state_pose.skeleton, allocator = Temp);
    InitSkeletonPose (*fright_pose, state_pose.skeleton, allocator = Temp);
    InitSkeletonPose (*bleft_pose, state_pose.skeleton, allocator = Temp);
    InitSkeletonPose (*bright_pose, state_pose.skeleton, allocator = Temp);
    InitSkeletonPose (*forward_pose, state_pose.skeleton, allocator = Temp);
    InitSkeletonPose (*backward_pose, state_pose.skeleton, allocator = Temp);
    InitSkeletonPose (*idle_pose, state_pose.skeleton, allocator = Temp);

    SampleAnimation (GetAnimation (.Human_Run_Left), elapsed_time * 30 * 1.2, *left_pose);
    SampleAnimation (GetAnimation (.Human_Run_Right), elapsed_time * 30 * 1.2, *right_pose);
    SampleAnimation (GetAnimation (.Human_Run_Forward_Left), elapsed_time * 30 * 1.2, *fleft_pose);
    SampleAnimation (GetAnimation (.Human_Run_Forward_Right), elapsed_time * 30 * 1.2, *fright_pose);
    SampleAnimation (GetAnimation (.Human_Run_Backward_Left), elapsed_time * 30 * 1.2, *bleft_pose);
    SampleAnimation (GetAnimation (.Human_Run_Backward_Right), elapsed_time * 30 * 1.2, *bright_pose);
    SampleAnimation (GetAnimation (.Human_Run_Forward), elapsed_time * 30 * 1.2, *forward_pose);
    SampleAnimation (GetAnimation (.Human_Run_Backward), elapsed_time * 30 * 1.2, *backward_pose);
    SampleAnimation (GetAnimation (.Human_Idle), elapsed_time * 30, *idle_pose);

    blend_space_poses : [9]*SkeletonPose = .[
        *idle_pose,
        *right_pose,
        *left_pose,
        *fright_pose,
        *fleft_pose,
        *bright_pose,
        *bleft_pose,
        *backward_pose,
        *forward_pose
    ];

    blend_space_positions : [9]Vec2f = .[
        .{0,0},
        .{-1,0}, .{1,0},
        Normalized (Vec2f.{-1, 1}), Normalized (Vec2f.{1, 1}),
        Normalized (Vec2f.{-1, -1}), Normalized (Vec2f.{1, -1}),
        .{0,-1}, .{0,1}
    ];

    blend_space_weights : [9]float = ---;

    blend_space_point := Vec2f.{smooth_movement_input.x, smooth_movement_input.z};
    CalculateBlendSpaceWeightsCartesian (blend_space_point, blend_space_positions, blend_space_weights);

    WeightedBlendPoses (*state_pose, blend_space_poses, blend_space_weights);
}

PlayerAirborneAnimState :: (machine : *AnimationStateMachine, using state : *AnimationState)
{
    Fall_Transition_Time :: 1.4;

    using data := cast (*PlayerAnimationData) machine.user_data;
    if is_on_ground
        TransitionToState (machine, "Grounded");
    if is_flying
        TransitionToState (machine, "Flying");
    if is_underwater
        TransitionToState (machine, "Underwater");

    jump_anim := GetAnimation (.Human_Jump_Forward);
    jump_to_fall_t := (elapsed_time - jump_anim.pose_count / 30.0) / Fall_Transition_Time;
    jump_to_fall_t = Clamp (jump_to_fall_t, 0, 1);

    jump_pose, fall_pose : SkeletonPose;
    InitSkeletonPose (*jump_pose, state_pose.skeleton, allocator = Temp);
    InitSkeletonPose (*fall_pose, state_pose.skeleton, allocator = Temp);

    jump_time := Clamp (elapsed_time * 30, 0, cast (float) jump_anim.pose_count - 1);

    SampleAnimation (jump_anim, jump_time, *jump_pose);
    SampleAnimation (GetAnimation (.Human_Fall_High), elapsed_time * 30, *fall_pose);

    BlendPoses (*state_pose, jump_pose, fall_pose, jump_to_fall_t);
}

PlayerFlyingAnimState :: (machine : *AnimationStateMachine, using state : *AnimationState)
{
    using data := cast (*PlayerAnimationData) machine.user_data;
    if !is_flying
        TransitionToState (machine, "Airborne");

    left_pose, right_pose, forward_pose, backward_pose, down_pose, up_pose, idle_pose : SkeletonPose;
    InitSkeletonPose (*left_pose, state_pose.skeleton, allocator = Temp);
    InitSkeletonPose (*right_pose, state_pose.skeleton, allocator = Temp);
    InitSkeletonPose (*forward_pose, state_pose.skeleton, allocator = Temp);
    InitSkeletonPose (*backward_pose, state_pose.skeleton, allocator = Temp);
    InitSkeletonPose (*down_pose, state_pose.skeleton, allocator = Temp);
    InitSkeletonPose (*up_pose, state_pose.skeleton, allocator = Temp);
    InitSkeletonPose (*idle_pose, state_pose.skeleton, allocator = Temp);

    SampleAnimation (GetAnimation (.Human_Flying_Left), elapsed_time * 30, *left_pose);
    SampleAnimation (GetAnimation (.Human_Flying_Right), elapsed_time * 30, *right_pose);
    SampleAnimation (GetAnimation (.Human_Flying_Forward), elapsed_time * 30, *forward_pose);
    SampleAnimation (GetAnimation (.Human_Flying_Backward), elapsed_time * 30, *backward_pose);
    SampleAnimation (GetAnimation (.Human_Flying_Down), elapsed_time * 30, *down_pose);
    SampleAnimation (GetAnimation (.Human_Flying_Up), elapsed_time * 30, *up_pose);
    SampleAnimation (GetAnimation (.Human_Flying_Idle), elapsed_time * 30, *idle_pose);

    blend_space_poses : [5]*SkeletonPose = .[
        *idle_pose,
        *right_pose,
        *left_pose,
        *backward_pose,
        *forward_pose
    ];

    blend_space_positions : [5]Vec2f = .[
        .{0,0}, .{-1,0}, .{1,0}, .{0,-1}, .{0,1}
    ];

    mult := 0.5;
    if IsKeyDown (SDLK_LSHIFT)
        mult = 1;

    blend_space_weights : [5]float = ---;

    blend_space_point := Vec2f.{smooth_movement_input.x, smooth_movement_input.z} * mult;
    CalculateBlendSpaceWeightsCartesian (blend_space_point, blend_space_positions, blend_space_weights);

    WeightedBlendPoses (*state_pose, blend_space_poses, blend_space_weights);
}

PlayerUnderwaterAnimState :: (machine : *AnimationStateMachine, using state : *AnimationState)
{
    using data := cast (*PlayerAnimationData) machine.user_data;
    if !is_underwater
        TransitionToState (machine, "Airborne");

    idle_pose, forward_pose, backward_pose : SkeletonPose;
    InitSkeletonPose (*idle_pose, state_pose.skeleton, allocator = Temp);
    InitSkeletonPose (*forward_pose, state_pose.skeleton, allocator = Temp);
    InitSkeletonPose (*backward_pose, state_pose.skeleton, allocator = Temp);

    SampleAnimation (GetAnimation (.Human_Swim_Underwater_Idle), elapsed_time * 30, *idle_pose);
    SampleAnimation (GetAnimation (.Human_Swim_Underwater_Forward), elapsed_time * 30, *forward_pose);
    SampleAnimation (GetAnimation (.Human_Swim_Underwater_Backward), elapsed_time * 30, *backward_pose);

    blend_space_poses : [3]*SkeletonPose = .[
        *idle_pose,
        *forward_pose,
        *backward_pose,
    ];

    blend_space_positions : [3]Vec2f = .[
        .{0,0}, .{0,1}, .{0,-1}
    ];

    blend_space_weights : [3]float = ---;

    blend_space_point := Vec2f.{smooth_movement_input.x, smooth_movement_input.z};
    CalculateBlendSpaceWeightsCartesian (blend_space_point, blend_space_positions, blend_space_weights);

    WeightedBlendPoses (*state_pose, blend_space_poses, blend_space_weights);
}
