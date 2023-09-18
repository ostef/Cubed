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
    vertex_count : s64;
    memory_block : *void;

    #place vertex_count;
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
    data, ok := read_entire_file (filename, log_errors = false);
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
