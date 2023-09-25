BlockInfo :: struct
{
    id : BlockID;
    mesh_type : ChunkMeshType;
    time_to_destroy := -1.0;    // In seconds

    // Must be between 0 and 1, otherwise  the intersection tests won't work
    box_min := Vec3f.{0,0,0};
    box_max := Vec3f.{1,1,1};
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
        time_to_destroy = 5,
    },
    .{
        id = .Bedrock,
        mesh_type = .Solid,
    },
    .{
        id = .Dirt,
        mesh_type = .Solid,
        time_to_destroy = 0.9,
    },
    .{
        id = .Grass,
        mesh_type = .Solid,
        time_to_destroy = 0.9,
    },
    .{
        id = .Sand,
        mesh_type = .Solid,
        time_to_destroy = 0.9,
    },
    .{
        id = .Gravel,
        mesh_type = .Solid,
        time_to_destroy = 0.9,
    },
    .{
        id = .Red_Sand,
        mesh_type = .Solid,
        time_to_destroy = 0.9,
    },
    .{
        id = .Snow,
        mesh_type = .Solid,
        time_to_destroy = 0.9,
    },
    .{
        id = .Snowy_Grass,
        mesh_type = .Solid,
        time_to_destroy = 0.9,
    },
    .{
        id = .Grass_Foliage,
        mesh_type = .Foliage,
        time_to_destroy = 0,
        box_min = .{0.25, 0, 0.25},
        box_max = .{0.75, 0.8, 0.75},
    },
];

// Check that:
//  * the Block_Infos array has the same number of elements than the BlockID enum,
//  * the Block_Infos array has elements in the same order as the BlockID enum, since this array is
// supposed to be indexed by BlockID values
//  * box_min and box_max for all block infos are within [0;1] range
#run
{
    Jai :: #import "Compiler";

    if Block_Infos.count != cast (int) BlockID.Count
    {
        Jai.compiler_report ("Block_Infos array count does not match the BlockID enum's", loc = #location (Block_Infos));
    }

    for it, i : Block_Infos
    {
        if i != cast (int) it.id
        {
            Jai.compiler_report (
                FormatString ("Invalid id in Block_Infos array at index %: expected % but got %", i, cast (BlockID) i, it.id),
                loc = #location (Block_Infos)
            );
        }

        if it.box_min.x < 0 || it.box_min.y < 0 || it.box_min.z < 0
        || it.box_min.x > 1 || it.box_min.y > 1 || it.box_min.z > 1
        {
            Jai.compiler_report (
                FormatString ("Invalid value for Block_Infos[%].box_min (%). Expected (x,y,z) between 0 and 1.", i, it.box_min),
                loc = #location (Block_Infos)
            );
        }

        if it.box_max.x < 0 || it.box_max.y < 0 || it.box_max.z < 0
        || it.box_max.x > 1 || it.box_max.y > 1 || it.box_max.z > 1
        {
            Jai.compiler_report (
                FormatString ("Invalid value for Block_Infos[%].box_max (%). Expected (x,y,z) between 0 and 1.", i, it.box_max),
                loc = #location (Block_Infos)
            );
        }
    }
};
