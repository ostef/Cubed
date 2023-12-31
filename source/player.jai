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

    block_is_selected : bool;
    selected_block : Vec3l;

    transform_matrix : Mat4f;

    anim_first_person_fsm : AnimationStateMachine;
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
    leading_foot : enum
    {
        Right;
        Left;
    };
    grounded_movement_t : float;
    destroying_block : bool;
}

Player_Fly_Toggle_Timer := 0.3; // seconds
Player_Height :: 1.8;
Player_Eyes_Height :: 1.55;
Player_Size :: 0.7;
Player_Movement_Speed :: 5.0;
Player_Jump_Height :: 1.05;
Player_Rotation_Speed :: 60.0;  // in degrees per second
Player_Rotation_Smoothing :: 0.3;
Block_Selection_Distance :: 4.5;
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

    InitAnimationStateMachine (*anim_first_person_fsm, *GetMesh (.Human_FPS).skeleton);
    anim_first_person_fsm.user_data = *anim_data;
    AddAnimationState (*anim_first_person_fsm, "Neutral", PlayerFirstPersonNeutralAnimState);
    AddAnimationState (*anim_first_person_fsm, "Destroying Block", PlayerFirstPersonDestroyingBlockAnimState);

    AddEventListener (*anim_first_person_fsm, "Punch", (machine : *AnimationStateMachine)
    {
        TransitionToState (machine, "Destroying Block", 0);
    });

    TransitionToState (*anim_first_person_fsm, "Neutral");
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

    movement_t := Length (Vec2f.{movement_input.x, movement_input.z});
    if !is_on_ground || is_flying || is_underwater
        movement_t = 0;

    anim_data.grounded_movement_t = Lerp (anim_data.grounded_movement_t, movement_t, 0.3);

    if IsMouseButtonPressed (SDL_BUTTON_LEFT)
        TriggerEvent (*anim_first_person_fsm, "Punch");

    transform_matrix = Mat4fTranslate (position) * Mat4fRotate (.{0, 1, 0}, orientation);
}

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

    player.anim_data.destroying_block = false;

    if hit_result.hit
    {
        player.block_is_selected = true;
        player.selected_block = .{hit_result.block_x, hit_result.block_y, hit_result.block_z};

        if !ImGui.GetIO ().WantCaptureMouse && (SDL_GetWindowFlags (g_window) & SDL_WINDOW_INPUT_FOCUS) != 0 && IsMouseButtonDown (SDL_BUTTON_LEFT)
        {
            player.anim_data.destroying_block = true;
            WorldDestroyBlock (world, hit_result.block_x, hit_result.block_y, hit_result.block_z);
        }
    }
    else
    {
        player.block_is_selected = false;
    }
}

UpdateThirdPersonPlayerAnimations :: (using player : *Player, delta_time : float)
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

UpdateFirstPersonPlayerAnimations :: (using player : *Player, delta_time : float)
{
    UpdateAnimationStateMachine (*anim_first_person_fsm, delta_time);

    // Sample screen gap additive for wide screen
    reference_pose, screen_gap_pose : SkeletonPose;
    InitSkeletonPose (*reference_pose, GetMesh (.Human_FPS), Temp);
    InitSkeletonPose (*screen_gap_pose, GetMesh (.Human_FPS), Temp);

    screen_w : s32;
    SDL_GetWindowSize (g_window, *screen_w, null);

    screen_gap_t := InverseLerp (640.0, 1920.0, cast (float) screen_w);
    screen_gap_t = Clamp (screen_gap_t, 0, 1);
    screen_gap_t *= GetAnimation (.Human_FPS_Screen_Gap).pose_count - 1;

    SampleAnimation (GetAnimation (.Human_FPS_Screen_Gap), screen_gap_t, *screen_gap_pose);
    SubtractPoses (*screen_gap_pose, reference_pose);
    AddPoses (*anim_first_person_fsm.final_pose, screen_gap_pose);

    GenerateSkinningMatrices (*anim_first_person_fsm.final_pose, true);
}

DrawThirdPersonPlayer :: (world : World, using player : Player, camera : Camera)
{
    GL_Utils.StateBlock (GL_ACTIVE_TEXTURE, (prev : GLenum) {glActiveTexture (prev);});
    GL_Utils.StateBlock (GL_TEXTURE_BINDING_2D_ARRAY, (prev : GLuint) {glBindTexture (GL_TEXTURE_2D_ARRAY, prev);});

    glActiveTexture (GL_TEXTURE0);
    glBindTexture (GL_TEXTURE_2D, g_steve_texture);

    if g_settings.show_skeletons
        DebugDrawSkeletonPose (anim_base_fsm.final_pose, transform_matrix, .{1,1,1,1});
    DrawSkinnedMesh (GetMesh (.Human), anim_base_fsm.final_pose, camera, transform_matrix);
}

DrawFirstPersonPlayer :: (world : World, using player : Player, camera : Camera)
{
    GL_Utils.StateBlock (GL_ACTIVE_TEXTURE, (prev : GLenum) {glActiveTexture (prev);});
    GL_Utils.StateBlock (GL_TEXTURE_BINDING_2D_ARRAY, (prev : GLuint) {glBindTexture (GL_TEXTURE_2D_ARRAY, prev);});

    glActiveTexture (GL_TEXTURE0);
    glBindTexture (GL_TEXTURE_2D, g_steve_texture);

    DrawSkinnedMesh (GetMesh (.Human_FPS), anim_first_person_fsm.final_pose, camera, .{});
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

    reference_anim := GetAnimation (.Human_Run_Forward);
    animation_time := elapsed_time * 30 * 1.2;
    normalized_anim_time := animation_time / cast (float) reference_anim.pose_count;
    normalized_anim_time -= Floor (normalized_anim_time);
    leading_foot = ifx normalized_anim_time > 0.5 then .Left else .Right;

    SampleAnimation (GetAnimation (.Human_Run_Left), animation_time, *left_pose);
    SampleAnimation (GetAnimation (.Human_Run_Right), animation_time, *right_pose);
    SampleAnimation (GetAnimation (.Human_Run_Forward_Left), animation_time, *fleft_pose);
    SampleAnimation (GetAnimation (.Human_Run_Forward_Right), animation_time, *fright_pose);
    SampleAnimation (GetAnimation (.Human_Run_Backward_Left), animation_time, *bleft_pose);
    SampleAnimation (GetAnimation (.Human_Run_Backward_Right), animation_time, *bright_pose);
    SampleAnimation (GetAnimation (.Human_Run_Forward), animation_time, *forward_pose);
    SampleAnimation (GetAnimation (.Human_Run_Backward), animation_time, *backward_pose);
    SampleAnimation (GetAnimation (.Human_Idle), animation_time, *idle_pose);

    blend_space_poses : [9]*SkeletonPose = .[
        *idle_pose,
        *left_pose,
        *right_pose,
        *fleft_pose,
        *fright_pose,
        *bleft_pose,
        *bright_pose,
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

    normalized_jump_time := elapsed_time * 30 / cast (float) jump_anim.pose_count;
    if leading_foot == .Right
        normalized_jump_time = Clamp (normalized_jump_time, 0, 0.5);
    else
        normalized_jump_time = Clamp (normalized_jump_time + 0.5, 0.5, 1);

    SampleAnimation (jump_anim, normalized_jump_time * jump_anim.pose_count, *jump_pose);
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
        *left_pose,
        *right_pose,
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

PlayerFirstPersonNeutralAnimState :: (machine : *AnimationStateMachine, using state : *AnimationState)
{
    using data := cast (*PlayerAnimationData) machine.user_data;

    if data.destroying_block
    {
        TransitionToState (machine, "Destroying Block");
    }

    idle_pose, run_pose : SkeletonPose;
    InitSkeletonPose (*idle_pose, machine.final_pose.skeleton, Temp);
    InitSkeletonPose (*run_pose, machine.final_pose.skeleton, Temp);

    SampleAnimation (GetAnimation (.Human_FPS_Idle), elapsed_time * 30, *idle_pose);
    SampleAnimation (GetAnimation (.Human_FPS_Run), elapsed_time * 30, *run_pose);

    BlendPoses (*state_pose, idle_pose, run_pose, grounded_movement_t);
}

PlayerFirstPersonDestroyingBlockAnimState :: (machine : *AnimationStateMachine, using state : *AnimationState)
{
    using data := cast (*PlayerAnimationData) machine.user_data;

    punch_anim := GetAnimation (.Human_FPS_Punch);
    animation_time := elapsed_time * 30;
    if !data.destroying_block && animation_time > cast (float) punch_anim.pose_count - 1
    {
        animation_time = 0;
        TransitionToState (machine, "Neutral", 0);
    }

    if data.destroying_block
        animation_time = Math.fmod_cycling (animation_time, 6);

    SampleAnimation (punch_anim, animation_time, *state_pose);
}
