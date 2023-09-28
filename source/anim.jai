// @Note: we mostly don't care about alignment when we allocate our memory.

AnimationID :: enum
{
    Human_Idle;
    Human_Breathing_Additive;
    Human_Sneak;
    Human_Run_Forward;
    Human_Run_Right;
    Human_Run_Left;
    Human_Run_Forward_Left;
    Human_Run_Forward_Right;
    Human_Run_Backward;
    Human_Run_Backward_Left;
    Human_Run_Backward_Right;
    Human_Shielding;
    Human_Swimming_Idle;
    Human_Jump_Forward;
    Human_Jump_Up;
    Human_Fall_High;
    Human_Flying_Idle;
    Human_Flying_Left;
    Human_Flying_Right;
    Human_Flying_Forward;
    Human_Flying_Backward;
    Human_Flying_Up;
    Human_Flying_Down;
    Human_Swim_Underwater_Idle;
    Human_Swim_Underwater_Forward;
    Human_Swim_Underwater_Backward;

    Count;
}

g_all_animations : [AnimationID.Count]SkeletalAnimation;

GetAnimation :: inline (id : AnimationID) -> *SkeletalAnimation #must
{
    return *g_all_animations[id];
}

JointSample :: struct
{
    local_position : Vec3f;
    local_orientation : Quatf;
    local_scale : Vec3f;
}

SkeletalAnimation :: struct
{
    joint_count : s64;
    pose_count : s64;
    memory_block : *void;
    name_to_joint_id : HashMap (string, s16);
    joint_samples : []JointSample;
}

JointPose :: struct
{
    parent : *JointPose;
    #as using sample : JointSample;
    // This is the transform matrix of the Joint in model space.
    // It is used for skinning matrices generation.
    model_space_transform : Mat4f;
}

SkeletonPose :: struct
{
    skeleton : *Skeleton;

    joint_count : s64;
    memory_block : *void;

    #place joint_count;
    joints : []JointPose;

    // The two members below might or might not be used,
    // since there may be other use cases for skeleton poses
    // than skinning (for example storing intermediate results
    // when combining two poses together). Although the skinning
    // matrices are always allocated in a block along with the
    // joints, the GL uniform buffer object isn't always initialized
    skinning_matrices : []Mat4f;
    skinning_data_ubo : GLuint;
}

LoadAllSkeletalAnimations :: () -> bool
{
    anims_info := type_info (AnimationID);
    for i : 0..anims_info.names.count - 2
    {
        name := anims_info.names[i];
        if !LoadSkeletalAnimationFromFile (*g_all_animations[i], FormatString ("data/anims/%.anim", name))
        {
            LogError ("Could not load skeletal animation %", name);
            return false;
        }
    }

    return true;
}

CalculateSkeletalAnimationMemoryBlockSize :: inline (joint_count : int, pose_count : int) -> int #must
{
    joint_name_size := size_of (SkeletalAnimation.name_to_joint_id.Entry)
        * HashMapGetMinCapacityForElementCount (SkeletalAnimation.name_to_joint_id.Load_Factor, joint_count)
        + joint_count * (Max_Skeleton_Joint_Name_Length + size_of (SkeletonJoint));
    sample_size := size_of (JointSample) * joint_count * pose_count;

    return joint_name_size + sample_size;
}

AllocSkeletalAnimationData :: (anim : *SkeletalAnimation, joint_count : int, pose_count : int, allocator := context.allocator)
{
    anim.memory_block = Alloc (CalculateSkeletalAnimationMemoryBlockSize (joint_count, pose_count), allocator);

    anim.joint_count = joint_count;
    anim.pose_count = pose_count;

    anim.joint_samples.data = anim.memory_block;
    anim.joint_samples.count = joint_count * pose_count;

    map_data := anim.memory_block + size_of (JointSample) * joint_count * pose_count;
    map_data += Max_Skeleton_Joint_Name_Length * joint_count;
    capacity := HashMapGetMinCapacityForElementCount (SkeletalAnimation.name_to_joint_id.Load_Factor, joint_count);
    HashMapInitFromPreallocatedMemory (*anim.name_to_joint_id, map_data, capacity, Trap);
}

GetJointNamesArray :: inline (using anim : SkeletalAnimation) -> [][Max_Skeleton_Joint_Name_Length]u8 #must
{
    result : [][Max_Skeleton_Joint_Name_Length]u8 = ---;
    result.count = joint_count;
    result.data = memory_block + size_of (JointSample) * joint_count * pose_count;

    return result;
}

GetJointName :: inline (anim : SkeletalAnimation, joint_id : s16) -> string #must
{
    Assert (joint_id >= 0 && joint_id < anim.joint_count, "Invalid joint id %", joint_id);

    names_data := cast (*[Max_Skeleton_Joint_Name_Length]u8) (anim.memory_block + size_of (JointSample) * anim.joint_count * anim.pose_count);

    return MakeString (names_data[joint_id].data);
}

GetJointSample :: inline (using anim : SkeletalAnimation, joint_id : s16, pose_index : int) -> *JointSample #must
{
    Assert (joint_id >= 0 && joint_id < joint_count, "Invalid joint id %", joint_id);
    Assert (pose_index >= 0 && pose_index < pose_count, "Pose index % out of bounds %", pose_index, pose_count);

    return *joint_samples[pose_index * joint_count + joint_id];
}

LoadSkeletalAnimationFromMemory :: (anim : *SkeletalAnimation, data : string, allocator := context.allocator) -> bool
{
    reader := MakeBinaryReader (data);

    str, ok := ReadString (*reader, "ANIMATION".count);
    if !ok || str != "ANIMATION"
        return false;

    version:, ok = ReadValue (*reader, u32);
    if !ok
    {
        LogError ("Could not read file version");
        return false;
    }

    if version != 10000
    {
        LogError ("Unknown version %", version);
        return false;
    }

    pose_count:, ok = ReadValue (*reader, u32);
    if !ok
    {
        LogError ("Could not read joint count");
        return false;
    }

    joint_count:, ok = ReadValue (*reader, u32);
    if !ok
    {
        LogError ("Could not read joint count");
        return false;
    }

    AllocSkeletalAnimationData (anim, joint_count, pose_count, allocator);
    joint_names := GetJointNamesArray (anim);

    for i : 0..joint_count - 1
    {
        name:, ok = ReadNullTerminatedString (*reader);
        if !ok
        {
            LogError ("Could not read joint % name", i);
            return false;
        }

        if name.count == 0 || name.count > Max_Skeleton_Joint_Name_Length
        {
            LogError ("Invalid joint name %", name);
            return false;
        }

        joint_name := joint_names[i].data;
        memcpy (joint_name, name.data, name.count + 1);
        name.data = joint_name;

        _, was_present := HashMapInsert (*anim.name_to_joint_id, name, xx i);
        if was_present
        {
            LogError ("Duplicate joint %", name);
            return false;
        }
    }

    ok = ReadArray (*reader, anim.joint_samples);
    if !ok
    {
        LogError ("Could not read joint samples");
        return false;
    }

    return true;
}

LoadSkeletalAnimationFromFile :: inline (anim : *SkeletalAnimation, filename : string, allocator := context.allocator) -> bool
{
    data, ok := read_entire_file (filename);
    if !ok
        return false;

    ok = LoadSkeletalAnimationFromMemory (anim, data, allocator);
    Free (data.data);

    return ok;
}

FreeSkeletalAnimation :: inline (using anim : *SkeletalAnimation, allocator : Allocator)
{
    Free (memory_block, allocator);
    Initialize (anim);
}

InitSkeletonPose :: (pose : *SkeletonPose, skeleton : *Skeleton, init_gl_objects := false, allocator := context.allocator)
{
    pose.skeleton = skeleton;
    pose.memory_block = Alloc ((size_of (JointPose) + size_of (Mat4f)) * skeleton.joints.count, allocator);

    pose.joints.data = pose.memory_block;
    pose.joints.count = skeleton.joints.count;
    Initialize (pose.joints.data, pose.joints.count);

    pose.skinning_matrices.data = xx (pose.joints.data + pose.joints.count);
    pose.skinning_matrices.count = skeleton.joints.count;
    Initialize (pose.skinning_matrices.data, pose.skinning_matrices.count);

    for * pose.joints
    {
        joint_in_skeleton := *skeleton.joints[it_index];
        if joint_in_skeleton.parent
        {
            parent_id := joint_in_skeleton.parent - skeleton.joints.data;
            it.parent = *pose.joints[parent_id];
        }
        else
        {
            it.parent = null;
        }
    }

    ResetToBindPose (pose);

    if init_gl_objects
        InitSkeletonPoseGLObjects (pose);
}

InitSkeletonPoseGLObjects :: (using pose : *SkeletonPose)
{
    GL_Utils.StateBlock (GL_UNIFORM_BUFFER_BINDING, (prev : GLuint) {glBindBuffer (GL_UNIFORM_BUFFER, prev);});

    glGenBuffers (1, *skinning_data_ubo);
    glBindBuffer (GL_UNIFORM_BUFFER, skinning_data_ubo);
    glBufferData (GL_UNIFORM_BUFFER, size_of (Mat4f) * Max_Joints, null, GL_DYNAMIC_DRAW);
}

FreeSkeletonPose :: inline (using pose : *SkeletonPose, allocator := context.allocator)
{
    Free (memory_block, allocator);
    if skinning_data_ubo != 0
        glDeleteBuffers (1, *skinning_data_ubo);

    Initialize (pose);
}

ResetToBindPose :: (using pose : *SkeletonPose)
{
    for * joints
    {
        it.local_position,
        it.local_orientation,
        it.local_scale = SimpleDecomposeTransform (skeleton.joints[it_index].local_bind_transform);
    }
}

InterpolateJointSamples :: inline (
    a : JointSample,
    b : JointSample,
    t : float
) -> JointSample #must
{
    result : JointSample = ---;
    result.local_position = Lerp (a.local_position, b.local_position, t);
    result.local_orientation = NLerp (a.local_orientation, b.local_orientation, t);
    result.local_scale = Lerp (a.local_scale, b.local_scale, t);

    return result;
}

SampleAnimation :: (
    anim : SkeletalAnimation,
    pose_index : float,
    pose : *SkeletonPose
)
{
    pose_index = Math.fmod_cycling (pose_index, cast (float) anim.pose_count);
    for * pose_joint : pose.joints
    {
        joint_name := GetJointName (pose.skeleton, cast (s16) it_index);
        anim_joint_id, exists := HashMapGet (*anim.name_to_joint_id, joint_name);
        if !exists
            continue;

        first_pose_index  := cast (s64) pose_index;
        second_pose_index := (first_pose_index + 1) % anim.pose_count;
        first  := GetJointSample (anim, anim_joint_id, first_pose_index);
        second := GetJointSample (anim, anim_joint_id, second_pose_index);
        pose_joint.sample = InterpolateJointSamples (
            first,
            second,
            Clamp (pose_index - first_pose_index, 0, 1)
        );
    }
}

// After we've done the sampling of the animation, and maybe other
// operations on the pose, we can calculate the pose transforms that
// will be used to generate the skinning matrices. This is a separate
// function from GenerateSkinningMatrices because we might need
// those transforms for purposes other than skinning.
CalculatePoseTransforms :: (using pose : *SkeletonPose)
{
    ProfileBlock ();

    for * joints
    {
        local_transform := Mat4fTranslate (it.local_position)
            * Mat4fScale (it.local_scale)
            * Mat4fFromQuat (it.local_orientation);

        parent := it.parent;
        if parent
            it.model_space_transform = parent.model_space_transform * local_transform;
        else
            it.model_space_transform = local_transform;
    }
}

GenerateSkinningMatrices :: (using pose : *SkeletonPose, upload_to_uniform_buffer : bool)
{
    CalculatePoseTransforms (pose);

    ProfileBlock ();

    if upload_to_uniform_buffer
    {
        for * skinning_matrices
        {
            it.* = Transposed (joints[it_index].model_space_transform * skeleton.joints[it_index].inverse_bind_transform);
        }

        if skinning_data_ubo == 0
            InitSkeletonPoseGLObjects (pose);

        GL_Utils.StateBlock (GL_UNIFORM_BUFFER_BINDING, (prev : GLuint) {glBindBuffer (GL_UNIFORM_BUFFER, prev);});

        glBindBuffer (GL_UNIFORM_BUFFER, skinning_data_ubo);
        glBufferSubData (GL_UNIFORM_BUFFER, 0, size_of (Mat4f) * skinning_matrices.count, skinning_matrices.data);
    }
    else
    {
        for * skinning_matrices
        {
            it.* = joints[it_index].model_space_transform * skeleton.joints[it_index].inverse_bind_transform;
        }
    }
}

CopyPose :: (dest : *SkeletonPose, src : SkeletonPose)
{
    Assert (dest.skeleton == src.skeleton, "Skeletons do not match");

    for * dest.joints
        it.sample = src.joints[it_index].sample;
}

BlendPoses :: (dest : *SkeletonPose, a : SkeletonPose, b : SkeletonPose, t : float)
{
    Assert (dest.skeleton == a.skeleton, "Skeletons do not match");
    Assert (dest.skeleton == b.skeleton, "Skeletons do not match");

    for i : 0..dest.joints.count - 1
        dest.joints[i].sample = InterpolateJointSamples (a.joints[i], b.joints[i], t);
}

CalculateBlendSpaceWeightsCartesian :: (point : Vec2f, positions : []Vec2f, result : []float)
{
    Assert (positions.count == result.count);

    total_weight := 0.0;
    for it, i : positions
    {
        dir := point - it;
        weight := 1.0;
        for other, j : positions
        {
            if i == j
                continue;

            other_dir := other - it;

            sqrd_length := Dot (other_dir, other_dir);
            new_weight := 1 - Dot (dir, other_dir) / sqrd_length;
            new_weight = Clamp (new_weight, 0, 1);
            weight = Min (weight, new_weight);
        }

        result[i] = weight;
        total_weight += weight;
    }

    for * result
        it.* /= total_weight;
}

CalculateBlendSpaceWeightsPolar :: (point : Vec2f, positions : []Vec2f, result : []float)
{
    Assert (positions.count == result.count);

    total_weight := 0.0;
    point_length := Length (point);
    for it, i : positions
    {
        length := Length (it);
        weight := 1.0;
        for other, j : positions
        {
            if i == j
                continue;

            other_length := Length (other);
            ij_avg_length := (length + other_length) * 0.5;

            ip_length := (point_length - length) * 0.5;
            ip_angle  := SignedAngle (it, point);
            ip_vector  := Vec2f.{ip_length, ip_angle * 2};

            ij_length := (other_length - length) * 0.5;
            ij_angle  := SignedAngle (it, other);
            ij_vector  := Vec2f.{ij_length, ij_angle * 2};

            sqrd_length := Dot (ij_vector, ij_vector);
            new_weight := 1 - Dot (ip_vector, ij_vector) / sqrd_length;
            new_weight = Clamp (new_weight, 0, 1);
            weight = Min (weight, new_weight);
        }

        result[i] = weight;
        total_weight += weight;
    }

    for * result
        it.* /= total_weight;
}

WeightedBlendPoses :: (dest : *SkeletonPose, poses : []*SkeletonPose, weights : []float)
{
    Assert (poses.count == weights.count);

    for * joint, joint_id : dest.joints
    {
        joint.local_position = .{0,0,0};
        joint.local_orientation = .{0,0,0,0};
        joint.local_scale = .{0,0,0};

        for pose, pose_index : poses
        {
            Assert (dest.skeleton == pose.skeleton);

            joint.local_position += weights[pose_index] * pose.joints[joint_id].local_position;

            if pose_index != 0 && Dot (joint.local_orientation, pose.joints[joint_id].local_orientation) < 0
                joint.local_orientation -= weights[pose_index] * pose.joints[joint_id].local_orientation;
            else
                joint.local_orientation += weights[pose_index] * pose.joints[joint_id].local_orientation;

            joint.local_scale += weights[pose_index] * pose.joints[joint_id].local_scale;
        }

        joint.local_orientation = Normalized (joint.local_orientation);
    }
}

AddPoses :: (dest : *SkeletonPose, other : SkeletonPose, weight := 1.0)
{
    Assert (dest.skeleton == other.skeleton);

    for * dest.joints
    {
        it.local_position += other.joints[it_index].local_position * weight;
        it.local_orientation *= NLerp (Quatf.{}, other.joints[it_index].local_orientation, weight);
        it.local_scale += other.joints[it_index].local_scale * weight;
    }
}

SubtractPoses :: (dest : *SkeletonPose, other : SkeletonPose, weight := 1.0)
{
    Assert (dest.skeleton == other.skeleton);

    for * dest.joints
    {
        it.local_position -= other.joints[it_index].local_position * weight;
        weighted_orientation := NLerp (Quatf.{}, other.joints[it_index].local_orientation, weight);
        it.local_orientation = Inverse (weighted_orientation) * it.local_orientation;
        it.local_scale -= other.joints[it_index].local_scale * weight;
    }
}
