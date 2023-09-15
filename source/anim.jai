#import "Binary_Reader";
#import "File";

// @Note: we mostly don't care about alignment when we allocate our memory.

MeshID :: enum
{
    Human;

    Count;
}

g_all_meshes : [MeshID.Count]SkinnedMesh;

GetMesh :: inline (id : MeshID) -> *SkinnedMesh #must
{
    return *g_all_meshes[id];
}

AnimationID :: enum
{
    Human_Idle;
    Human_Breathing_Additive;
    Human_Sneak;
    Human_Walk;
    Human_Sprint;
    Human_Shielding;
    Human_Swimming_Idle;

    Count;
}

g_all_animations : [AnimationID.Count]SkeletalAnimation;

GetAnimation :: inline (id : AnimationID) -> *SkeletalAnimation #must
{
    return *g_all_animations[id];
}

SkinnedVertex :: struct
{
    position : Vec3f;
    normal : Vec3f;
    tex_coords : Vec2f;
    joint_id : s16;
}

SkinnedMesh :: struct
{
    vao, vbo, ibo : GLuint;

    index_count : s64;
    _vertex_count : s64;
    memory_block : *void;

    #place _vertex_count;
    vertices : []SkinnedVertex;
    indices : []u32;

    using, except (memory_block) skeleton : Skeleton;
}

Max_Skeleton_Joint_Name_Length :: 64;

SkeletonJoint :: struct
{
    id : s16;
    local_bind_transform : Mat4f;
    inverse_bind_transform : Mat4f;
    parent : *SkeletonJoint;
}

Skeleton :: struct
{
    joint_count : s64;
    memory_block : *void;

    #place joint_count;
    joints : []SkeletonJoint;
    name_to_joint_id : HashMap (string, s16);
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

CalculateSkeletonMemoryBlockSize :: inline (joint_count : int) -> int #must
{
    map_capacity := HashMapGetMinCapacityForElementCount (Skeleton.name_to_joint_id.Load_Factor, joint_count);

    return size_of (SkeletonJoint) * joint_count
        + Max_Skeleton_Joint_Name_Length * joint_count
        + size_of (Skeleton.name_to_joint_id.Entry) * map_capacity;
}

AllocSkeletonData :: (skeleton : *Skeleton, joint_count : int, allocator := context.allocator)
{
    size := CalculateSkeletonMemoryBlockSize (joint_count);
    skeleton.joint_count = joint_count;
    skeleton.memory_block = Alloc (size, allocator);

    // This below is redundant since joints.data has the same offset as memory_block
    // skeleton.joints.data = skeleton.memory_block;
    // skeleton.joints.count = joint_count;

    map_data := skeleton.memory_block + size_of (SkeletonJoint) * joint_count;
    map_data += Max_Skeleton_Joint_Name_Length * joint_count;
    capacity := HashMapGetMinCapacityForElementCount (Skeleton.name_to_joint_id.Load_Factor, joint_count);
    HashMapInitFromPreallocatedMemory (*skeleton.name_to_joint_id, map_data, capacity, Trap);
}

GetJointNamesArray :: inline (skeleton : Skeleton) -> [][Max_Skeleton_Joint_Name_Length]u8 #must
{
    result : [][Max_Skeleton_Joint_Name_Length]u8 = ---;
    result.count = skeleton.joint_count;
    result.data = skeleton.memory_block + size_of (SkeletonJoint) * skeleton.joint_count;

    return result;
}

GetJointName :: inline (skeleton : Skeleton, joint_id : s16) -> string #must
{
    Assert (joint_id >= 0 && joint_id < skeleton.joint_count, "Invalid joint id %", joint_id);

    names_data := cast (*[Max_Skeleton_Joint_Name_Length]u8) (skeleton.memory_block + size_of (SkeletonJoint) * skeleton.joint_count);

    return MakeString (names_data[joint_id].data);
}

LoadSkinnedMeshFromMemory :: (mesh : *SkinnedMesh, data : string, init_gl_objects := true, allocator := context.allocator) -> bool
{
    reader := MakeBinaryReader (data);

    str, ok := ReadString (*reader, "SKINNED_MESH".count);
    if !ok || str != "SKINNED_MESH"
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

    vertex_count:, ok = ReadValue (*reader, u32);
    if !ok
    {
        LogError ("Could not read vertex count");
        return false;
    }

    triangle_count:, ok = ReadValue (*reader, u32);
    if !ok
    {
        LogError ("Could not read triangle count");
        return false;
    }

    index_count := triangle_count * 3;

    mesh.memory_block = Alloc (size_of (SkinnedVertex) * vertex_count + size_of (u32) * index_count, allocator);

    mesh.vertices.data = mesh.memory_block;
    mesh.vertices.count = xx vertex_count;

    mesh.indices.data = xx (mesh.vertices.data + vertex_count);
    mesh.indices.count = xx index_count;
    mesh.index_count = xx index_count;

    ok = ReadArray (*reader, mesh.vertices);
    if !ok
    {
        LogError ("Could not read vertices");
        return false;
    }

    ok = ReadArray (*reader, mesh.indices);
    if !ok
    {
        LogError ("Could not read indices");
        return false;
    }

    joint_count:, ok = ReadValue (*reader, s16);
    if !ok
    {
        LogError ("Could not read joint count");
        return false;
    }

    AllocSkeletonData (*mesh.skeleton, joint_count, allocator);
    joint_names := GetJointNamesArray (*mesh.skeleton);

    for i : 0..joint_count - 1
    {
        name:, ok = ReadNullTerminatedString (*reader);
        if !ok
        {
            LogError ("Could not read joint % name", i);
            return false;
        }

        if name.count == 0 || name.count >= Max_Skeleton_Joint_Name_Length
        {
            LogError ("Invalid joint name %", name);
            return false;
        }

        joint_name := joint_names[i].data;
        memcpy (joint_name, name.data, name.count + 1);
        name.data = joint_name;

        _, was_present := HashMapInsert (*mesh.name_to_joint_id, name, i);
        if was_present
        {
            LogError ("Duplicate joint %", name);
            return false;
        }

        joint := *mesh.joints[i];
        joint.id = i;
        joint.local_bind_transform, ok = ReadValue (*reader, Mat4f);
        if !ok
        {
            LogError ("Could not read joint % local transform", name);
            return false;
        }

        parent_id:, ok = ReadValue (*reader, s16);
        if !ok
        {
            LogError ("Could not read joint % parent id", name);
            return false;
        }

        if parent_id >= 0
        {
            if parent_id >= mesh.joints.count
            {
                LogError ("Invalid parent id for joint %", name);
                return false;
            }

            joint.parent = *mesh.joints[parent_id];
            joint.inverse_bind_transform = joint.parent.inverse_bind_transform * joint.local_bind_transform;
        }
        else
        {
            joint.parent = null;
            joint.inverse_bind_transform = joint.local_bind_transform;
        }
    }

    for * mesh.joints
        it.inverse_bind_transform = Inverse (it.inverse_bind_transform);

    if init_gl_objects
        InitSkinnedMeshGLObjects (mesh);

    return true;
}

LoadSkinnedMeshFromFile :: inline (mesh : *SkinnedMesh, filename : string, init_gl_objects := true, allocator := context.allocator) -> bool
{
    data, ok := read_entire_file (filename);
    if !ok
    {
        LogError ("Could not read file '%'", filename);
        return false;
    }

    ok = LoadSkinnedMeshFromMemory (mesh, data, init_gl_objects, allocator);
    Free (data.data);

    return ok;
}

LoadAllSkinnedMeshes :: () -> bool
{
    meshes_info := type_info (MeshID);
    for i : 0..meshes_info.names.count - 2
    {
        name := meshes_info.names[i];
        if !LoadSkinnedMeshFromFile (*g_all_meshes[i], FormatString ("data/meshes/%.mesh", name))
        {
            LogError ("Could not load skinned mesh %", name);
            return false;
        }
    }

    return true;
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

InitSkinnedMeshGLObjects :: (using mesh : *SkinnedMesh)
{
    GL_Utils.StateBlock (GL_VERTEX_ARRAY_BINDING, (prev : GLuint) {glBindVertexArray (prev);});
    GL_Utils.StateBlock (GL_ARRAY_BUFFER_BINDING, (prev : GLuint) {glBindBuffer (GL_ARRAY_BUFFER, prev);});
    GL_Utils.StateBlock (GL_ELEMENT_ARRAY_BUFFER_BINDING, (prev : GLuint) {glBindBuffer (GL_ELEMENT_ARRAY_BUFFER, prev);});

    glGenVertexArrays (1, *vao);
    glGenBuffers (2, *vbo);

    glBindVertexArray (vao);
    glBindBuffer (GL_ARRAY_BUFFER, vbo);
    glBindBuffer (GL_ELEMENT_ARRAY_BUFFER, ibo);

    glBufferData (GL_ARRAY_BUFFER, size_of (SkinnedVertex) * vertices.count, vertices.data, GL_STATIC_DRAW);
    glBufferData (GL_ELEMENT_ARRAY_BUFFER, size_of (u32) * indices.count, indices.data, GL_STATIC_DRAW);

    SetupVertexAttribsForShader (mesh, g_skinned_mesh_shader);
}

SetupVertexAttribsForShader :: (using mesh : *SkinnedMesh, shader : GLuint)
{
    location : GLint;

    location = glGetAttribLocation (shader, "a_Position");
    if location != -1
    {
        glEnableVertexAttribArray (xx location);
        glVertexAttribPointer (xx location, 3, GL_FLOAT, GL_FALSE, size_of (SkinnedVertex), xx OffsetOf (SkinnedVertex, "position"));
    }

    location = glGetAttribLocation (shader, "a_Normal");
    if location != -1
    {
        glEnableVertexAttribArray (xx location);
        glVertexAttribPointer (xx location, 3, GL_FLOAT, GL_FALSE, size_of (SkinnedVertex), xx OffsetOf (SkinnedVertex, "normal"));
    }

    location = glGetAttribLocation (shader, "a_Tex_Coords");
    if location != -1
    {
        glEnableVertexAttribArray (xx location);
        glVertexAttribPointer (xx location, 2, GL_FLOAT, GL_FALSE, size_of (SkinnedVertex), xx OffsetOf (SkinnedVertex, "tex_coords"));
    }

    location = glGetAttribLocation (shader, "a_Joint_Id");
    if location != -1
    {
        glEnableVertexAttribArray (xx location);
        glVertexAttribIPointer (xx location, 1, GL_UNSIGNED_SHORT, size_of (SkinnedVertex), xx OffsetOf (SkinnedVertex, "joint_id"));
    }
}

FreeSkinnedMeshData :: inline (mesh : *SkinnedMesh, allocator := context.allocator)
{
    Free (mesh.memory_block, allocator);
    mesh.vertices = .[];
    mesh.indices = .[];
}

FreeSkeleton :: inline (using skeleton : *Skeleton, allocator := context.allocator)
{
    Free (*memory_block, allocator);
    Initialize (skeleton);
}

DestroySkinnedMeshGLObjects :: inline (using mesh : *SkinnedMesh)
{
    glDeleteBuffers (2, *vbo);
    glDeleteVertexArrays (1, *vao);
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
    {
        LogError ("Could not read file '%'", filename);
        return false;
    }

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

