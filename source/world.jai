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

    Count;
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

BlockBreakingInfo :: struct
{
    x, y, z : s64;
    stage : float;
    updated_this_frame : bool;
}

World :: struct
{
    ChunkMap :: HashMap (Vec2l, *Chunk, hash_func = HashVec2l, comp_func = (a, b) => a == b);

    #as using generator : Generator;
    origin_chunk : *Chunk;
    all_loaded_chunks : ChunkMap;
    // Volatile: all the Chunks in this map are being modified in another thread
    chunks_being_generated : ChunkMap;
    chunk_generation_thread_group : Threads.Thread_Group;

    blocks_being_broken : [..]BlockBreakingInfo;
    blocks_being_broken_vao, blocks_being_broken_vbo : GLuint;
}

BlockGetMeshType :: inline (block : BlockID) -> ChunkMeshType #must
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

        glEnableVertexAttribArray (g_block_shader_attribs.position);
        glVertexAttribPointer (g_block_shader_attribs.position, 3, GL_FLOAT, GL_FALSE, size_of (BlockVertex), cast (*void) OffsetOf (BlockVertex, "position"));

        glEnableVertexAttribArray (g_block_shader_attribs.face);
        glVertexAttribIPointer (g_block_shader_attribs.face, 1, GL_UNSIGNED_BYTE, size_of (BlockVertex), cast (*void) OffsetOf (BlockVertex, "face"));

        glEnableVertexAttribArray (g_block_shader_attribs.block_id);
        glVertexAttribIPointer (g_block_shader_attribs.block_id, 1, GL_UNSIGNED_BYTE, size_of (BlockVertex), cast (*void) OffsetOf (BlockVertex, "block_id"));

        glEnableVertexAttribArray (g_block_shader_attribs.face_corner);
        glVertexAttribIPointer (g_block_shader_attribs.face_corner, 1, GL_UNSIGNED_BYTE, size_of (BlockVertex), cast (*void) OffsetOf (BlockVertex, "corner"));

        glEnableVertexAttribArray (g_block_shader_attribs.block_height);
        glVertexAttribPointer (g_block_shader_attribs.block_height, 1, GL_FLOAT, GL_FALSE, size_of (BlockVertex), cast (*void) OffsetOf (BlockVertex, "block_height"));

        glEnableVertexAttribArray (g_block_shader_attribs.temperature);
        glVertexAttribPointer (g_block_shader_attribs.temperature, 1, GL_FLOAT, GL_FALSE, size_of (BlockVertex), cast (*void) OffsetOf (BlockVertex, "temperature"));

        glEnableVertexAttribArray (g_block_shader_attribs.humidity);
        glVertexAttribPointer (g_block_shader_attribs.humidity, 1, GL_FLOAT, GL_FALSE, size_of (BlockVertex), cast (*void) OffsetOf (BlockVertex, "humidity"));
    }
}

ChunkCleanup :: inline (chunk : *Chunk)
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
    result.min = .{xx (x * Chunk_Size), 0, xx (z * Chunk_Size)};
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

ChunkSetBlockInChunk :: inline (chunk : *Chunk, x : s64, y : s64, z : s64, block : Block)
{
    #if Enable_Chunk_Bounds_Check
    {
        Assert (x >= 0 && x < Chunk_Size, "Invalid x coordinate (got %)", x);
        Assert (y >= 0 && y < Chunk_Height, "Invalid y coordinate (got %)", y);
        Assert (z >= 0 && z < Chunk_Size, "Invalid z coordinate (got %)", z);
    }

    chunk.blocks[ChunkBlockIndex (x, y, z)] = block;

    chunk.is_dirty = true;
    if x == 0 && chunk.west
        chunk.west.is_dirty = true;
    else if x == Chunk_Size - 1 && chunk.east
        chunk.east.is_dirty = true;

    if z == 0 && chunk.south
        chunk.south.is_dirty = true;
    else if z == Chunk_Size - 1 && chunk.north
        chunk.north.is_dirty = true;
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

BiomeGetSurfaceBlock :: inline (world : World, chunk : *Chunk, biome : Biome, surface_height : float, x : s64, y : s64, z : s64) -> Block #must
{
    isurface_height := cast (int) surface_height;
    if y < world.water_level
        return .{id=biome.flooded_surface_block};
    else if y == isurface_height
        return .{id=biome.surface_top_block};
    else
        return .{id=biome.surface_block};
}

#no_reset
Offsets : [Perlin_Fractal_Max_Octaves]Vec3f;
#no_reset
Offsets2 : [Perlin_Fractal_Max_Octaves]Vec3f;

#run {
    PerlinGenerateOffsets (*context.random_number_generator, Offsets);
    PerlinGenerateOffsets (*context.random_number_generator, Offsets2);
};

Cheese_Cave_Noise_Params := NoiseParams.{
    scale = 0.0478,
    octaves = 4,
    persistance = 0.545,
    lacunarity = 0.323
};

Cheese_Cave_Threshold := 0.245;

Spaggetti_Cave_Noise_Params := NoiseParams.{
    scale = 0.03283,
    octaves = 3,
    persistance = 0.345,
    lacunarity = 1.738
};

Spaggetti_Cave_Threshold := 0.245;

Noodle_Cave_Noise_Params := NoiseParams.{
    scale = 0.03283,
    octaves = 3,
    persistance = 0.345,
    lacunarity = 1.738
};

Noodle_Cave_Threshold := 0.245;

// Careful: this routine must be thread safe!
ChunkGenerate :: (world : World, chunk : *Chunk)
{
    if chunk.is_generated
        return;

    defer chunk.is_generated = true;

    ProfileBlock ();

    surface_thickness_rng : RNG;
    RandomSeed (*surface_thickness_rng, world.seed + 57483593 + HashS64 (chunk.x) + HashS64 (chunk.z));

    surface_height_map : [Chunk_Size * Chunk_Size]float = ---;
    surface_thickness_map : [Chunk_Size * Chunk_Size]float = ---;
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
                biome := *Biomes[chunk.biome_values[index].biome_id];

                surface_height_map[index] = terrain_params[TerrainParam.Surface_Height];
                surface_thickness_map[index] = biome.surface_layer_thickness + RandomRangeFloat (*surface_thickness_rng, -biome.surface_layer_fluctuation, biome.surface_layer_fluctuation);
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
                surface_index := ChunkBlockIndex (x, 0, z);
                surface_height := surface_height_map[surface_index];
                surface_thickness := surface_thickness_map[surface_index];
                biome_id := chunk.biome_values[surface_index].biome_id;
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
                else if y > cast (int) (surface_height - surface_thickness)
                {
                    chunk.blocks[index] = BiomeGetSurfaceBlock (world, chunk, biome, surface_height, x, y, z);
                }
                // else if y == cast (int) surface_height
                // {
                //     chunk.blocks[index].id = biome.surface_block;
                // }
                // else if y > cast (int) surface_height - 5
                // {
                //     chunk.blocks[index].id = .Dirt;
                // }
                else if y > cast (int) (surface_height - 15)
                {
                    chunk.blocks[index].id = .Stone;
                }
                else
                {
                    // Noodle caves threshold ~ 0.1
                    // Spaggetti caves threshold ~ 0.1

                    sample_x := x + chunk.x * Chunk_Size;
                    sample_z := z + chunk.z * Chunk_Size;

                    is_air := false;
                    cheese_cave_value := PerlinFractalNoise (Cheese_Cave_Noise_Params, Offsets, xx sample_x, xx y, xx sample_z);
                    cheese_cave_value /= PerlinFractalMax (Cheese_Cave_Noise_Params.octaves, Cheese_Cave_Noise_Params.persistance);
                    cheese_cave_value = (cheese_cave_value + 1) * 0.5;
                    if cheese_cave_value < Cheese_Cave_Threshold
                    {
                        is_air = true;
                    }
                    else
                    {
                        spaggetti1 := PerlinFractalNoise (Spaggetti_Cave_Noise_Params, Offsets, xx sample_x, xx y, xx sample_z);
                        spaggetti1 /= PerlinFractalMax (Spaggetti_Cave_Noise_Params.octaves, Spaggetti_Cave_Noise_Params.persistance);
                        spaggetti2 := PerlinFractalNoise (Spaggetti_Cave_Noise_Params, Offsets, xx sample_x, xx y + 40.0, xx sample_z);
                        spaggetti2 /= PerlinFractalMax (Spaggetti_Cave_Noise_Params.octaves, Spaggetti_Cave_Noise_Params.persistance);
                        spaggetti_cave_value := (spaggetti1 * spaggetti1 + spaggetti2 * spaggetti2) / Spaggetti_Cave_Threshold;

                        if spaggetti_cave_value < Spaggetti_Cave_Threshold
                        {
                            is_air = true;
                        }
                        else
                        {
                            noodle1 := PerlinFractalNoise (Noodle_Cave_Noise_Params, Offsets2, xx sample_x, xx y, xx sample_z);
                            noodle1 /= PerlinFractalMax (Noodle_Cave_Noise_Params.octaves, Noodle_Cave_Noise_Params.persistance);
                            noodle2 := PerlinFractalNoise (Noodle_Cave_Noise_Params, Offsets2, xx sample_x, xx y + 40.0, xx sample_z);
                            noodle2 /= PerlinFractalMax (Noodle_Cave_Noise_Params.octaves, Noodle_Cave_Noise_Params.persistance);
                            noodle_cave_value := (noodle1 * noodle1 + noodle2 * noodle2) / Noodle_Cave_Threshold;

                            if noodle_cave_value < Noodle_Cave_Threshold
                                is_air = true;
                        }
                    }

                    if is_air
                        chunk.blocks[index].id = .Air;
                    else
                        chunk.blocks[index].id = .Stone;
                }
            }
        }
    }
}

PushBlockVertices :: (
    vertices : *[..]BlockVertex,
    block : BlockID,
    position : Vec3f,
    visible_faces : BlockFaceFlags,
    block_height : float,
    temperature : float,
    humidity : float
)
{
    PushVertex :: (face : BlockFace, corner : BlockFaceCorner) -> *BlockVertex #must #expand
    {
        v := ArrayPush (`vertices);
        v.block_id = cast (u8) `block;
        v.position = `position;
        v.block_height = `block_height;
        v.temperature = `temperature;
        v.humidity = `humidity;
        v.face = face;
        v.corner = corner;

        return v;
    }

    if visible_faces & .East
    {
        v := PushVertex (.East, .Bottom_Left);
        v.position += .{1, 0, 0};

        v = PushVertex (.East, .Top_Left);
        v.position += .{1, block_height, 0};

        v = PushVertex (.East, .Top_Right);
        v.position += .{1, block_height, 1};

        v = PushVertex (.East, .Bottom_Left);
        v.position += .{1, 0, 0};

        v = PushVertex (.East, .Top_Right);
        v.position += .{1, block_height, 1};

        v = PushVertex (.East, .Bottom_Right);
        v.position += .{1, 0, 1};
    }

    if visible_faces & .West
    {
        v := PushVertex (.West, .Bottom_Right);
        v.position += .{0, 0, 0};

        v = PushVertex (.West, .Top_Left);
        v.position += .{0, block_height, 1};

        v = PushVertex (.West, .Top_Right);
        v.position += .{0, block_height, 0};

        v = PushVertex (.West, .Bottom_Right);
        v.position += .{0, 0, 0};

        v = PushVertex (.West, .Bottom_Left);
        v.position += .{0, 0, 1};

        v = PushVertex (.West, .Top_Left);
        v.position += .{0, block_height, 1};
    }

    if visible_faces & .Above
    {
        v := PushVertex (.Above, .Bottom_Left);
        v.position += .{0, block_height, 0};

        v = PushVertex (.Above, .Top_Right);
        v.position += .{1, block_height, 1};

        v = PushVertex (.Above, .Bottom_Right);
        v.position += .{1, block_height, 0};

        v = PushVertex (.Above, .Bottom_Left);
        v.position += .{0, block_height, 0};

        v = PushVertex (.Above, .Top_Left);
        v.position += .{0, block_height, 1};

        v = PushVertex (.Above, .Top_Right);
        v.position += .{1, block_height, 1};
    }

    if visible_faces & .Below
    {
        v := PushVertex (.Below, .Top_Left);
        v.position += .{0, 0, 0};

        v = PushVertex (.Below, .Top_Right);
        v.position += .{1, 0, 0};

        v = PushVertex (.Below, .Bottom_Right);
        v.position += .{1, 0, 1};

        v = PushVertex (.Below, .Top_Left);
        v.position += .{0, 0, 0};

        v = PushVertex (.Below, .Bottom_Right);
        v.position += .{1, 0, 1};

        v = PushVertex (.Below, .Bottom_Left);
        v.position += .{0, 0, 1};
    }

    if visible_faces & .North
    {
        v := PushVertex (.North, .Bottom_Right);
        v.position += .{0, 0, 1};

        v = PushVertex (.North, .Bottom_Left);
        v.position += .{1, 0, 1};

        v = PushVertex (.North, .Top_Left);
        v.position += .{1, block_height, 1};

        v = PushVertex (.North, .Bottom_Right);
        v.position += .{0, 0, 1};

        v = PushVertex (.North, .Top_Left);
        v.position += .{1, block_height, 1};

        v = PushVertex (.North, .Top_Right);
        v.position += .{0, block_height, 1};
    }

    if visible_faces & .South
    {
        v := PushVertex (.South, .Bottom_Left);
        v.position += .{0, 0, 0};

        v = PushVertex (.South, .Top_Right);
        v.position += .{1, block_height, 0};

        v = PushVertex (.South, .Bottom_Right);
        v.position += .{1, 0, 0};

        v = PushVertex (.South, .Bottom_Left);
        v.position += .{0, 0, 0};

        v = PushVertex (.South, .Top_Left);
        v.position += .{0, block_height, 0};

        v = PushVertex (.South, .Top_Right);
        v.position += .{1, block_height, 0};
    }
}

BlockGetHeight :: inline (chunk : *Chunk, x : s64, y : s64, z : s64) -> float #must
{
    block := ChunkGetBlock (chunk, x, y, z);
    above := ChunkGetBlock (chunk, x, y + 1, z);
    if block.id == .Water && above.id != .Water
            return 14.0 / 16.0;

    return 1;
}

BlockGetHeight :: inline (chunk : *Chunk, block : Block, x : s64, y : s64, z : s64) -> float #must
{
    above := ChunkGetBlock (chunk, x, y + 1, z);
    if block.id == .Water && above.id != .Water
        return 14.0 / 16.0;

    return 1;
}

BlockGetVisibleFaces :: inline (chunk : *Chunk, block : Block, x : s64, y : s64, z : s64) -> BlockFaceFlags #must, height : float
{
    mesh_type := BlockGetMeshType (block);
    block_height := BlockGetHeight (chunk, block, x, y, z);

    east  := ChunkGetBlock (chunk, x + 1, y, z);
    west  := ChunkGetBlock (chunk, x - 1, y, z);
    above := ChunkGetBlock (chunk, x, y + 1, z);
    below := ChunkGetBlock (chunk, x, y - 1, z);
    north := ChunkGetBlock (chunk, x, y, z + 1);
    south := ChunkGetBlock (chunk, x, y, z - 1);

    visible_faces : BlockFaceFlags;
    if BlockGetMeshType (east) != mesh_type || BlockGetHeight (chunk, east, x + 1, y, z) != block_height
        visible_faces |= .East;
    if BlockGetMeshType (west) != mesh_type || BlockGetHeight (chunk, west, x - 1, y, z) != block_height
        visible_faces |= .West;
    if BlockGetMeshType (above) != mesh_type || block_height != 1
        visible_faces |= .Above;
    if BlockGetMeshType (below) != mesh_type || BlockGetHeight (chunk, below, x, y - 1, z) != 1
        visible_faces |= .Below;
    if BlockGetMeshType (north) != mesh_type || BlockGetHeight (chunk, north, x, y, z + 1) != block_height
        visible_faces |= .North;
    if BlockGetMeshType (south) != mesh_type || BlockGetHeight (chunk, south, x, y, z - 1) != block_height
        visible_faces |= .South;

    return visible_faces, block_height;
}

ChunkPushVertices :: (chunk : *Chunk, vertices : *[..]BlockVertex, mesh_type : ChunkMeshType)
{
    position := Vec3f.{xx (chunk.x * Chunk_Size), 0, xx (chunk.z * Chunk_Size)};
    for y : 0..Chunk_Height - 1
    {
        for z : 0..Chunk_Size - 1
        {
            for x : 0..Chunk_Size - 1
            {
                block := ChunkGetBlockInChunk (chunk, x, y, z);
                if BlockGetMeshType (block) != mesh_type
                    continue;

                visible_faces, block_height := BlockGetVisibleFaces (chunk, block, x, y, z);
                biome_values := chunk.biome_values[ChunkBlockIndex (x, 0, z)];

                PushBlockVertices (
                    vertices,
                    block,
                    position + Vec3f.{xx x, xx y, xx z},
                    visible_faces,
                    block_height,
                    Min (biome_values.temperature / 3.0, 1.0),
                    Min (biome_values.humidity / 3.0, 1.0)
                );
            }
        }
    }
}

ChunkGenerateMeshes :: (chunk : *Chunk)
{
    if !chunk.is_dirty
        return;

    ProfileBlock ();

    defer chunk.is_dirty = false;

    state := GetTemporaryStorageState ();
    defer SetTemporaryStorageState (state);

    vertices : [..]BlockVertex;
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

        glBufferData (GL_ARRAY_BUFFER, size_of (BlockVertex) * vertices.count, vertices.data, GL_DYNAMIC_DRAW);

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

    AddGlobalProfilingData (*context.profiling_entries);

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

    GL_Utils.StateBlock (GL_VERTEX_ARRAY_BINDING, (prev : GLuint) {glBindVertexArray (prev);});
    GL_Utils.StateBlock (GL_ARRAY_BUFFER_BINDING, (prev : GLuint) {glBindBuffer (GL_ARRAY_BUFFER, prev);});

    glGenVertexArrays (1, *world.blocks_being_broken_vao);
    glGenBuffers (1, *world.blocks_being_broken_vbo);

    glBindVertexArray (world.blocks_being_broken_vao);
    glBindBuffer (GL_ARRAY_BUFFER, world.blocks_being_broken_vbo);

    glEnableVertexAttribArray (0);
    glVertexAttribPointer (0, 3, GL_FLOAT, GL_FALSE, size_of (StaticVertex), cast (*void) OffsetOf (StaticVertex, "position"));

    glEnableVertexAttribArray (1);
    glVertexAttribPointer (1, 3, GL_FLOAT, GL_FALSE, size_of (StaticVertex), cast (*void) OffsetOf (StaticVertex, "normal"));

    glEnableVertexAttribArray (2);
    glVertexAttribPointer (2, 2, GL_FLOAT, GL_FALSE, size_of (StaticVertex), cast (*void) OffsetOf (StaticVertex, "tex_coords"));
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
    ProfileBlock ();

    completed := Threads.get_completed_work (*chunk_generation_thread_group);
    for completed
    {
        data := cast (*ChunkGenerationWorkerData) it;

        Free (data.logging_name.data);

        HashMapRemove (*chunks_being_generated, .{data.chunk.x, data.chunk.z});
        WorldAddChunk (world, data.chunk);

        Free (data);
    }
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
    ProfileBlock ();

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

WorldBreakBlock :: (using world : *World, x : s64, y : s64, z : s64)
{
    break_info : *BlockBreakingInfo;
    index := -1;
    for * blocks_being_broken
    {
        if it.x == x && it.y == y && it.z == z
        {
            break_info = it;
            index = it_index;
            break;
        }
    }

    if !break_info
    {
        break_info = ArrayPush (*blocks_being_broken);
        break_info.x = x;
        break_info.y = y;
        break_info.z = z;
        index = blocks_being_broken.count - 1;
    }

    break_info.updated_this_frame = true;
}

WorldUpdateBreakingBlocks :: (using world : *World, delta_time : float)
{
    for * blocks_being_broken
    {
        if !it.updated_this_frame
        {
            remove it;
            continue;
        }

        chunk_x, chunk_z := ChunkPositionFromWorldPosition (it.x, it.z);
        chunk := WorldGetChunk (world, chunk_x, chunk_z);
        Assert (chunk != null, "Breaking block of a chunk that isn't loaded");

        rel_x, rel_z := ChunkAbsoluteToRelativeCoordinates (chunk_x, chunk_z, it.x, it.z);

        it.stage += delta_time * 6;

        if it.stage > 9
        {
            ChunkSetBlockInChunk (chunk, rel_x, it.y, rel_z, .{id=.Air});

            remove it;
            continue;
        }

        it.updated_this_frame = false;
    }
}
