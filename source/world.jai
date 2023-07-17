BlockFace :: enum u8
{
    East;
    West;
    Above;
    Below;
    North;
    South;
}

BlockFaceFlags :: enum_flags
{
    East;
    West;
    Above;
    Below;
    North;
    South;
}

BlockFaceCorner :: enum u8
{
    Top_Left;
    Top_Right;
    Bottom_Left;
    Bottom_Right;
}

BlockID :: enum u8
{
    Air;
    Water;
    Stone;
    Bedrock;
    Dirt;
    Grass;
    Sand;
    Gravel;
    Red_Sand;
    Snow;
    Snowy_Grass;
}

Block :: struct
{
    #as id : BlockID;
}

Chunk_Size :: 16;
Chunk_Height :: 384;

ChunkMeshType :: enum u8
{
    Solid;
    Water;

    Count;

    Invisible;
}

Chunk :: struct
{
    east, west, north, south : *Chunk;
    x, z : s64;
    is_dirty, is_generated : bool;

    total_vertex_count : s64;
    vertex_counts : [ChunkMeshType.Count]s64;
    vaos : [ChunkMeshType.Count]GLuint;
    vbos : [ChunkMeshType.Count]GLuint;
    biome_values : [Chunk_Size * Chunk_Size]BiomeValues;
    blocks : [Chunk_Size * Chunk_Size * Chunk_Height]Block;
}

HashS64 :: inline (val : s64) -> u64 #must
{
    h := val;
    h ^= h >>> 33;
    h *= 0xff51afd7ed558ccd;
    h ^= h >>> 33;
    h *= 0xc4ceb9fe1a85ec53;
    h ^= h >>> 33;

    return cast (u64) h;
}

HashVec2l :: inline (vec : Vec2l) -> u64 #must
{
    result : u64 = 0;
    result ^= HashS64 (vec.x) + 0x9e3779b9;
    result ^= HashS64 (vec.y) + 0x9e3779b9 + (result << 6) + (result >> 2);

    return result;
}

World :: struct
{
    #as using generator : Generator;
    origin_chunk : *Chunk;
    all_loaded_chunks : HashMap (Vec2l, *Chunk, hash_func = HashVec2l, comp_func = (a, b) => a == b);
    // Volatile: all the Chunks in this map are being modified in another thread
    chunks_being_generated : HashMap (Vec2l, *Chunk, hash_func = HashVec2l, comp_func = (a, b) => a == b);
    chunk_generation_thread_group : Threads.Thread_Group;
}

GetBlockMeshType :: inline (block : BlockID) -> ChunkMeshType #must
{
    if block ==
    {
    case .Air;
        return .Invisible;
    case .Water;
        return .Water;
    case;
        return .Solid;
    }
}

ChunkInit :: (chunk : *Chunk, x : s64, z : s64)
{
    chunk.x = x;
    chunk.z = z;
    chunk.is_dirty = true;

    glGenVertexArrays (chunk.vaos.count, chunk.vaos.data);
    glGenBuffers (chunk.vbos.count, chunk.vbos.data);

    GL_Utils.StateBlock (GL_VERTEX_ARRAY_BINDING, (prev : GLuint) {glBindVertexArray (prev);});
    GL_Utils.StateBlock (GL_ARRAY_BUFFER_BINDING, (prev : GLuint) {glBindBuffer (GL_ARRAY_BUFFER, prev);});

    for i : 0..ChunkMeshType.Count - 1
    {
        glBindVertexArray (chunk.vaos[i]);
        glBindBuffer (GL_ARRAY_BUFFER, chunk.vbos[i]);

        glEnableVertexAttribArray (0);
        glVertexAttribPointer (0, 3, GL_FLOAT, GL_FALSE, size_of (Vertex), cast (*void) OffsetOf (Vertex, "position"));

        glEnableVertexAttribArray (1);
        glVertexAttribIPointer (1, 1, GL_UNSIGNED_BYTE, size_of (Vertex), cast (*void) OffsetOf (Vertex, "face"));

        glEnableVertexAttribArray (2);
        glVertexAttribIPointer (2, 1, GL_UNSIGNED_BYTE, size_of (Vertex), cast (*void) OffsetOf (Vertex, "block_id"));

        glEnableVertexAttribArray (3);
        glVertexAttribIPointer (3, 1, GL_UNSIGNED_BYTE, size_of (Vertex), cast (*void) OffsetOf (Vertex, "corner"));

        glEnableVertexAttribArray (4);
        glVertexAttribPointer (4, 1, GL_FLOAT, GL_FALSE, size_of (Vertex), cast (*void) OffsetOf (Vertex, "block_height"));
    }
}

ChunkCleanup :: (chunk : *Chunk)
{
    glDeleteVertexArrays (chunk.vaos.count, chunk.vaos.data);
    glDeleteBuffers (chunk.vbos.count, chunk.vbos.data);

    if chunk.east
    {
        chunk.east.west = null;
        chunk.east.is_dirty = true;
    }

    if chunk.west
    {
        chunk.west.east = null;
        chunk.west.is_dirty = true;
    }

    if chunk.south
    {
        chunk.south.north = null;
        chunk.south.is_dirty = true;
    }

    if chunk.north
    {
        chunk.north.south = null;
        chunk.north.is_dirty = true;
    }
}

ChunkAABB :: inline (x : s64, z : s64) -> AABB #must
{
    result : AABB = ---;
    result.min = .{xx (x / Chunk_Size), 0, xx (z / Chunk_Size)};
    result.max = result.min + .{xx Chunk_Size, xx Chunk_Height, xx Chunk_Size};

    return result;
}

BlockAABB :: inline (x : s64, y : s64, z : s64) -> AABB #must
{
    result : AABB = ---;
    result.min = .{xx x, xx y, xx z};
    result.max = result.min + .{1, 1, 1};

    return result;
}

ChunkAbsoluteToRelativeCoordinates :: inline (chunk_x : s64, chunk_z : s64, x : s64, z : s64) -> x : s64, z : s64
{
    return cast (int) (x - chunk_x * Chunk_Size), cast (int) (z - chunk_z * Chunk_Size);
}

ChunkPositionFromWorldPosition :: inline (x : s64, z : s64) -> x : s64, z : s64
{
    return
        (x + cast (s64) (x < 0)) / Chunk_Size - cast (s64) (x < 0),
        (z + cast (s64) (z < 0)) / Chunk_Size - cast (s64) (z < 0);
}

ChunkBlockIndex :: inline (x : s64, y : s64, z : s64) -> s64 #must
{
    return y * Chunk_Size * Chunk_Size + z * Chunk_Size + x;
}

ChunkGetAtRelativeCoordinates :: (chunk : *Chunk, x : s64, z : s64) -> *Chunk #must, new_x : s64, new_z : s64
{
    while chunk && x < 0
    {
        chunk = chunk.west;
        x += Chunk_Size;
    }
    while chunk && x >= Chunk_Size
    {
        chunk = chunk.east;
        x -= Chunk_Size;
    }
    while chunk && z < 0
    {
        chunk = chunk.south;
        z += Chunk_Size;
    }
    while chunk && z >= Chunk_Size
    {
        chunk = chunk.north;
        z -= Chunk_Size;
    }

    return chunk, x, z;
}

ChunkGetBlockInChunk :: inline (chunk : *Chunk, x : s64, y : s64, z : s64) -> Block #must
{
    #if Enable_Chunk_Bounds_Check
    {
        Assert (x >= 0 && x < Chunk_Size, "Invalid x coordinate (got %)", x);
        Assert (z >= 0 && z < Chunk_Size, "Invalid z coordinate (got %)", z);
    }

    if y < 0 || y >= Chunk_Height
        return .{id = .Air};

    return chunk.blocks[ChunkBlockIndex (x, y, z)];
}

ChunkGetBlock :: inline (chunk : *Chunk, x : s64, y : s64, z : s64) -> Block #must
{
    if y < 0 || y >= Chunk_Height
        return .{id = .Air};

    chunk, x, z = ChunkGetAtRelativeCoordinates (chunk, x, z);
    if !chunk
        return .{id = .Air};

    return ChunkGetBlockInChunk (chunk, x, y, z);
}

// Careful: this routine must be thread safe!
ChunkGenerate :: (world : World, chunk : *Chunk)
{
    if chunk.is_generated
        return;

    defer chunk.is_generated = true;

    surface_height_map : [Chunk_Size * Chunk_Size]float = ---;
    {
        terrain_params : [TerrainParam.Count]float = ---;
        for z : 0..Chunk_Size - 1
        {
            for x : 0..Chunk_Size - 1
            {
                sample_x := x + chunk.x * Chunk_Size;
                sample_z := z + chunk.z * Chunk_Size;

                index := ChunkBlockIndex (x, 0, z);
                CalculateTerrainParams (world, *terrain_params, xx sample_x, xx sample_z);
                chunk.biome_values[index] = CalculateBiomeValuesFromTerrainParams (terrain_params);
                surface_height_map[index] = terrain_params[TerrainParam.Surface_Height];
            }
        }
    }

    for y : 0..Chunk_Height - 1
    {
        for z : 0..Chunk_Size - 1
        {
            for x : 0..Chunk_Size - 1
            {
                index := ChunkBlockIndex (x, y, z);
                surface_height := surface_height_map[ChunkBlockIndex (x, 0, z)];
                biome_id := chunk.biome_values[ChunkBlockIndex (x, 0, z)].biome_id;
                biome := *Biomes[biome_id];

                if y == 0
                {
                    chunk.blocks[index].id = .Bedrock;
                }
                else if y > cast (int) surface_height
                {
                    if y <= world.surface_params.water_level
                        chunk.blocks[index].id = biome.fluid_block;
                    else
                        chunk.blocks[index].id = .Air;
                }
                else if y > cast (int) surface_height - 5
                {
                    chunk.blocks[index].id = biome.surface_block;
                }
                else
                {
                    chunk.blocks[index].id = .Stone;
                }
            }
        }
    }
}

PushBlockVertices :: (vertices : *[..]Vertex, block : BlockID, position : Vec3f, visible_faces : BlockFaceFlags, block_height := 1.0)
{
    if visible_faces & .East
    {
        v := ArrayPush (vertices, .{position, block_height, .East, .Bottom_Left, xx block});
        v.position += .{1, 0, 0};

        v = ArrayPush (vertices, .{position, block_height, .East, .Top_Left, xx block});
        v.position += .{1, block_height, 0};

        v = ArrayPush (vertices, .{position, block_height, .East, .Top_Right, xx block});
        v.position += .{1, block_height, 1};

        v = ArrayPush (vertices, .{position, block_height, .East, .Bottom_Left, xx block});
        v.position += .{1, 0, 0};

        v = ArrayPush (vertices, .{position, block_height, .East, .Top_Right, xx block});
        v.position += .{1, block_height, 1};

        v = ArrayPush (vertices, .{position, block_height, .East, .Bottom_Right, xx block});
        v.position += .{1, 0, 1};
    }

    if visible_faces & .West
    {
        v := ArrayPush (vertices, .{position, block_height, .West, .Bottom_Right, xx block});
        v.position += .{0, 0, 0};

        v = ArrayPush (vertices, .{position, block_height, .West, .Top_Left, xx block});
        v.position += .{0, block_height, 1};

        v = ArrayPush (vertices, .{position, block_height, .West, .Top_Right, xx block});
        v.position += .{0, block_height, 0};

        v = ArrayPush (vertices, .{position, block_height, .West, .Bottom_Right, xx block});
        v.position += .{0, 0, 0};

        v = ArrayPush (vertices, .{position, block_height, .West, .Bottom_Left, xx block});
        v.position += .{0, 0, 1};

        v = ArrayPush (vertices, .{position, block_height, .West, .Top_Left, xx block});
        v.position += .{0, block_height, 1};
    }

    if visible_faces & .Above
    {
        v := ArrayPush (vertices, .{position, block_height, .Above, .Bottom_Left, xx block});
        v.position += .{0, block_height, 0};

        v = ArrayPush (vertices, .{position, block_height, .Above, .Top_Right, xx block});
        v.position += .{1, block_height, 1};

        v = ArrayPush (vertices, .{position, block_height, .Above, .Bottom_Right, xx block});
        v.position += .{1, block_height, 0};

        v = ArrayPush (vertices, .{position, block_height, .Above, .Bottom_Left, xx block});
        v.position += .{0, block_height, 0};

        v = ArrayPush (vertices, .{position, block_height, .Above, .Top_Left, xx block});
        v.position += .{0, block_height, 1};

        v = ArrayPush (vertices, .{position, block_height, .Above, .Top_Right, xx block});
        v.position += .{1, block_height, 1};
    }

    if visible_faces & .Below
    {
        v := ArrayPush (vertices, .{position, block_height, .Below, .Top_Left, xx block});
        v.position += .{0, 0, 0};

        v = ArrayPush (vertices, .{position, block_height, .Below, .Top_Right, xx block});
        v.position += .{1, 0, 0};

        v = ArrayPush (vertices, .{position, block_height, .Below, .Bottom_Right, xx block});
        v.position += .{1, 0, 1};

        v = ArrayPush (vertices, .{position, block_height, .Below, .Top_Left, xx block});
        v.position += .{0, 0, 0};

        v = ArrayPush (vertices, .{position, block_height, .Below, .Bottom_Right, xx block});
        v.position += .{1, 0, 1};

        v = ArrayPush (vertices, .{position, block_height, .Below, .Bottom_Left, xx block});
        v.position += .{0, 0, 1};
    }

    if visible_faces & .North
    {
        v := ArrayPush (vertices, .{position, block_height, .North, .Bottom_Right, xx block});
        v.position += .{0, 0, 1};

        v = ArrayPush (vertices, .{position, block_height, .North, .Bottom_Left, xx block});
        v.position += .{1, 0, 1};

        v = ArrayPush (vertices, .{position, block_height, .North, .Top_Left, xx block});
        v.position += .{1, block_height, 1};

        v = ArrayPush (vertices, .{position, block_height, .North, .Bottom_Right, xx block});
        v.position += .{0, 0, 1};

        v = ArrayPush (vertices, .{position, block_height, .North, .Top_Left, xx block});
        v.position += .{1, block_height, 1};

        v = ArrayPush (vertices, .{position, block_height, .North, .Top_Right, xx block});
        v.position += .{0, block_height, 1};
    }

    if visible_faces & .South
    {
        v := ArrayPush (vertices, .{position, block_height, .South, .Bottom_Left, xx block});
        v.position += .{0, 0, 0};

        v = ArrayPush (vertices, .{position, block_height, .South, .Top_Right, xx block});
        v.position += .{1, block_height, 0};

        v = ArrayPush (vertices, .{position, block_height, .South, .Bottom_Right, xx block});
        v.position += .{1, 0, 0};

        v = ArrayPush (vertices, .{position, block_height, .South, .Bottom_Left, xx block});
        v.position += .{0, 0, 0};

        v = ArrayPush (vertices, .{position, block_height, .South, .Top_Left, xx block});
        v.position += .{0, block_height, 0};

        v = ArrayPush (vertices, .{position, block_height, .South, .Top_Right, xx block});
        v.position += .{1, block_height, 0};
    }
}

ChunkPushVertices :: (chunk : *Chunk, vertices : *[..]Vertex, mesh_type : ChunkMeshType)
{
    position := Vec3f.{xx (chunk.x * Chunk_Size), 0, xx (chunk.z * Chunk_Size)};
    for y : 0..Chunk_Height - 1
    {
        for z : 0..Chunk_Size - 1
        {
            for x : 0..Chunk_Size - 1
            {
                block := ChunkGetBlockInChunk (chunk, x, y, z);
                if GetBlockMeshType (block) != mesh_type
                    continue;

                top_block := ChunkGetBlock (chunk, x, y + 1, z);
                bottom_block := ChunkGetBlock (chunk, x, y - 1, z);

                block_height : float = ---;
                if block.id == .Water && top_block.id != .Water
                    block_height = 14.0 / 16.0;
                else
                    block_height = 8.0 / 16.0;

                visible_faces : BlockFaceFlags;
                if GetBlockMeshType (ChunkGetBlock (chunk, x + 1, y, z)) != mesh_type
                    visible_faces |= .East;
                if GetBlockMeshType (ChunkGetBlock (chunk, x - 1, y, z)) != mesh_type
                    visible_faces |= .West;
                if GetBlockMeshType (top_block) != mesh_type
                    visible_faces |= .Above;
                if GetBlockMeshType (bottom_block) != mesh_type
                    visible_faces |= .Below;
                if GetBlockMeshType (ChunkGetBlock (chunk, x, y, z + 1)) != mesh_type
                    visible_faces |= .North;
                if GetBlockMeshType (ChunkGetBlock (chunk, x, y, z - 1)) != mesh_type
                    visible_faces |= .South;

                PushBlockVertices (vertices, block, position + Vec3f.{xx x, xx y, xx z}, visible_faces, block_height);
            }
        }
    }
}

ChunkGenerateMeshes :: (chunk : *Chunk)
{
    if !chunk.is_dirty
        return;

    defer chunk.is_dirty = false;

    state := GetTemporaryStorageState ();
    defer SetTemporaryStorageState (state);

    vertices : [..]Vertex;
    vertices.allocator = Temp;
    ArrayReserve (*vertices, 12000);

    GL_Utils.StateBlock (GL_VERTEX_ARRAY_BINDING, (prev : GLuint) {glBindVertexArray (prev);});
    GL_Utils.StateBlock (GL_ARRAY_BUFFER_BINDING, (prev : GLuint) {glBindBuffer (GL_ARRAY_BUFFER, prev);});

    chunk.total_vertex_count = 0;
    for i : 0..ChunkMeshType.Count - 1
    {
        ChunkPushVertices (chunk, *vertices, xx i);
        chunk.vertex_counts[i] = vertices.count;
        chunk.total_vertex_count += vertices.count;

        glBindVertexArray (chunk.vaos[i]);
        glBindBuffer (GL_ARRAY_BUFFER, chunk.vbos[i]);

        glBufferData (GL_ARRAY_BUFFER, size_of (Vertex) * vertices.count, vertices.data, GL_DYNAMIC_DRAW);

        ArrayClear (*vertices);
    }
}

#scope_file

ChunkGenerationWorkerData :: struct
{
    logging_name : string;
    world : *World;
    chunk : *Chunk;
}

ChunkGenerationWorkerProc :: (group : *Threads.Thread_Group, thread : *Threads.Thread, work : *void) -> Threads.Thread_Continue_Status
{
    using data := cast (*ChunkGenerationWorkerData) work;
    ChunkGenerate (world, chunk);

    return .CONTINUE;
}

WorldInitBase :: inline (world : *World)
{
    Initialize (world);

    world.all_loaded_chunks.allocator = context.allocator;
    world.chunks_being_generated.allocator = context.allocator;

    thread_count := Clamp (System.get_number_of_processors (.ALL_LOGICAL) - 1, 2, 200);
    Threads.init (*world.chunk_generation_thread_group, thread_count, ChunkGenerationWorkerProc);
    world.chunk_generation_thread_group.name = "ChunkGeneration";
    world.chunk_generation_thread_group.logging = false;

    Threads.start (*world.chunk_generation_thread_group);
}

#scope_export

WorldInit :: inline (world : *World, seed : u64)
{
    WorldInitBase (world);
    GeneratorInit (world, seed);
}

WorldInit :: inline (world : *World, seed : u64, surface_params : SurfaceParams)
{
    WorldInitBase (world);
    GeneratorInit (world, seed, surface_params);
}

WorldFree :: (using world : *World)
{
    for all_loaded_chunks
    {
        ChunkCleanup (it);
        Free (it);
    }

    HashMapFree (*all_loaded_chunks);
    HashMapFree (*chunks_being_generated);
    SplineFree (surface_params.spline);
    surface_params.spline = null;
    Threads.shutdown (*chunk_generation_thread_group);
}

WorldGetChunk :: inline (world : *World, x : s64, z : s64) -> *Chunk #must
{
    return HashMapGet (*world.all_loaded_chunks, .{x, z});
}

WorldCreateChunk :: (world : *World, x : s64, z : s64) -> *Chunk #must
{
    chunk := WorldGetChunk (world, x, z);
    if chunk
        return chunk;

    chunk = Alloc (Chunk);
    ChunkInit (chunk, x, z);
    WorldAddChunk (world, chunk);

    return chunk;
}

WorldAddChunk :: (world : *World, chunk : *Chunk)
{
    Assert (WorldGetChunk (world, chunk.x, chunk.z) == null, "Tried adding a chunk that already exists at x:% z:%", chunk.x, chunk.z);

    chunk.is_dirty = true;
    chunk.east  = WorldGetChunk (world, chunk.x + 1, chunk.z);
    chunk.west  = WorldGetChunk (world, chunk.x - 1, chunk.z);
    chunk.north = WorldGetChunk (world, chunk.x, chunk.z + 1);
    chunk.south = WorldGetChunk (world, chunk.x, chunk.z - 1);

    if chunk.east
    {
        chunk.east.west = chunk;
        chunk.east.is_dirty = true;
    }

    if chunk.west
    {
        chunk.west.east = chunk;
        chunk.west.is_dirty = true;
    }

    if chunk.north
    {
        chunk.north.south = chunk;
        chunk.north.is_dirty = true;
    }

    if chunk.south
    {
        chunk.south.north = chunk;
        chunk.south.is_dirty = true;
    }

    HashMapInsert (*world.all_loaded_chunks, .{chunk.x, chunk.z}, chunk);
}

WorldHandleNewlyGeneratedChunks :: (using world : *World)
{
    completed := Threads.get_completed_work (*chunk_generation_thread_group);
    for completed
    {
        data := cast (*ChunkGenerationWorkerData) it;

        Free (data.logging_name.data);

        HashMapRemove (*chunks_being_generated, .{data.chunk.x, data.chunk.z});
        WorldAddChunk (world, data.chunk);

        Free (data);
    }

    // if completed.count > 0
    //     LogMessage ("Generated % new chunks", completed.count);
}

WorldLaunchThreadedChunkGeneration :: inline (using world : *World, x : s64, z : s64)
{
    // Check if the chunk generation has already been launched
    if HashMapGet (*chunks_being_generated, .{x, z})
        return;

    chunk := Alloc (Chunk);
    ChunkInit (chunk, x, z);
    HashMapInsert (*chunks_being_generated, .{x, z}, chunk);

    data := Alloc (ChunkGenerationWorkerData);
    data.world = world;
    data.chunk = chunk;
    if world.chunk_generation_thread_group.logging
        data.logging_name = FormatString ("Chunk (%, %)", x, z);

    Threads.add_work (*chunk_generation_thread_group, data, data.logging_name);
}

WorldGenerateAroundPosition :: (world : *World, position : Vec3f, distance_in_chunks : int)
{
    chunk_x, chunk_z := ChunkPositionFromWorldPosition (cast (s64) position.x, cast (s64) position.z);

    for z : chunk_z - distance_in_chunks..chunk_z + distance_in_chunks
    {
        for x : chunk_x - distance_in_chunks..chunk_x + distance_in_chunks
        {
            horizontal_pos := Vec2f.{position.x, position.z};
            chunk_pos := Vec2f.{xx (x * Chunk_Size), xx (z * Chunk_Size)};

            if Distance (horizontal_pos, chunk_pos) < xx (distance_in_chunks * Chunk_Size)
            {
                if WorldGetChunk (world, x, z)
                    continue;

                WorldLaunchThreadedChunkGeneration (world, x, z);
            }
        }
    }
}
