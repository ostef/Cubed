AnimationStateProc :: #type (*AnimationStateMachine, *AnimationState);

AnimationState :: struct
{
    elapsed_time : float;
    state_pose : SkeletonPose;
    name : string;
    proc : AnimationStateProc;
}

AnimationStateMachine :: struct
{
    states : HashMap (string, AnimationState);

    current_state : *AnimationState;
    next_state : *AnimationState;
    transition_t : float;
    time_to_transition : float;
    transition_source_location : Source_Code_Location;

    final_pose : SkeletonPose;

    user_data : *void;
}

InitAnimationStateMachine :: (using machine : *AnimationStateMachine, skeleton : *Skeleton, allocator := context.allocator)
{
    InitSkeletonPose (*final_pose, skeleton, allocator = allocator);
    states.allocator = allocator;
}

AddAnimationState :: (using machine : *AnimationStateMachine, name : string, proc : AnimationStateProc)
{
    state, exists := HashMapInsert (*states, name, .{name=name, proc=proc});
    if exists
    {
        LogWarning ("Overwriting existing animation state '%'", name);
    }

    InitSkeletonPose (*state.state_pose, final_pose.skeleton, allocator = machine.states.allocator);
}

TransitionToState :: (using machine : *AnimationStateMachine, name : string, transition_time_in_seconds := 0.1, location := #caller_location)
{
    if transition_source_location == location
        return;

    state := HashMapGetPtr (*states, name);
    if !state
    {
        LogError ("Transitionning to invalid animation state '%'", name);
        return;
    }

    if !current_state
    {
        current_state = state;
        return;
    }

    next_state = state;
    next_state.elapsed_time = 0;
    transition_t = 0;
    time_to_transition = transition_time_in_seconds;
    transition_source_location = location;
}

UpdateAnimationStateMachine :: (using machine : *AnimationStateMachine, delta_time : float)
{
    if current_state
    {
        current_state.proc (machine, current_state);
        current_state.elapsed_time += delta_time;
    }

    if next_state
    {
        next_state.proc (machine, next_state);
        next_state.elapsed_time += delta_time;
    }

    if next_state
    {
        BlendPoses (*final_pose, current_state.state_pose, next_state.state_pose, transition_t);

        transition_t += delta_time / time_to_transition;
        if transition_t >= 1
        {
            current_state.elapsed_time = 0;
            current_state = next_state;
            next_state = null;
            transition_t = 0;
            transition_source_location = .{};
        }
    }
    else if current_state
    {
        CopyPose (*final_pose, current_state.state_pose);
    }
}
