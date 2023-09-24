BlockInfo :: struct
{
    id : BlockID;
    mesh_type : ChunkMeshType;
    time_to_destroy := -1.0;    // In seconds
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
    Grass_Foliage;

    Count;
}

Block_Infos :: BlockInfo.[
    .{
        id = .Air,
        mesh_type = .Invisible,
    },
    .{
        id = .Water,
        mesh_type = .Water,
    },
    .{
        id = .Stone,
        mesh_type = .Solid,
        time_to_destroy = 10,
    },
    .{
        id = .Bedrock,
        mesh_type = .Solid,
    },
    .{
        id = .Dirt,
        mesh_type = .Solid,
        time_to_destroy = 1,
    },
    .{
        id = .Grass,
        mesh_type = .Solid,
        time_to_destroy = 1,
    },
    .{
        id = .Sand,
        mesh_type = .Solid,
        time_to_destroy = 1,
    },
    .{
        id = .Gravel,
        mesh_type = .Solid,
        time_to_destroy = 1,
    },
    .{
        id = .Red_Sand,
        mesh_type = .Solid,
        time_to_destroy = 1,
    },
    .{
        id = .Snow,
        mesh_type = .Solid,
        time_to_destroy = 0.5,
    },
    .{
        id = .Snowy_Grass,
        mesh_type = .Solid,
        time_to_destroy = 1,
    },
    .{
        id = .Grass_Foliage,
        mesh_type = .Foliage,
        time_to_destroy = 0,
    },
];

// Check that the Block_Infos array has:
//  * the same number of elements than the BlockID enum
//  * elements in the same order as the BlockID enum, since this array is
// supposed to be indexed by BlockID values
#run
{
    Jai :: #import "Compiler";

    if Block_Infos.count != cast (int) BlockID.Count
    {
        Jai.compiler_report ("Block_Infos array count does not match the BlockID enum's", loc = #location (Block_Infos));
    }

    for it1, i : Block_Infos
    {
        if i != cast (int) it1.id
        {
            Jai.compiler_report (
                FormatString ("Invalid id in Block_Infos array at index %: expected % but got %", i, cast (BlockID) i, it1.id),
                loc = #location (Block_Infos)
            );
        }
    }
};
