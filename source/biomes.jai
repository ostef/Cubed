Biome :: struct
{
    name : string;
    color := Vec4f.{0,0,0,1};
    temperature : float;
    downfall : float;
    has_precipitations := true;

    surface_top_block : BlockID;
    surface_block : BlockID;
    flooded_surface_block : BlockID;
    fluid_block := BlockID.Water;
    surface_layer_thickness := 5.0;
    surface_layer_fluctuation := 3.0;
}

Biomes :: Biome.[
    .{
        name="Void",
        color=.{ 0, 0, 0, 1},
        temperature=0.5,
        downfall=0.5,
        has_precipitations=false,
    },
    .{
        name="Ocean",
        color=.{ 0.18, 0.4, 0.94, 1},
        temperature=0.5,
        downfall=0.5,
        surface_top_block=.Gravel,
        surface_block=.Gravel,
        flooded_surface_block=.Gravel,
    },
    .{
        name="Deep Ocean",
        color=.{ 0.1, 0.14, 0.62, 1},
        temperature=0.5,
        downfall=0.5,
        surface_top_block=.Gravel,
        surface_block=.Gravel,
        flooded_surface_block=.Gravel,
    },
    .{
        name="Warm Ocean",
        color=.{ 0.06, 0.16, 0.95, 1},
        temperature=0.5,
        downfall=0.5,
        surface_top_block=.Gravel,
        surface_block=.Gravel,
        flooded_surface_block=.Gravel,
    },
    .{
        name="Cold Ocean",
        color=.{ 0.16, 0.58, 0.98, 1},
        temperature=0.5,
        downfall=0.5,
        surface_top_block=.Gravel,
        surface_block=.Gravel,
        flooded_surface_block=.Gravel,
    },
    .{
        name="Deep Cold Ocean",
        color=.{ 0.03, 0.29, 0.53, 1},
        temperature=0.5,
        downfall=0.5,
        surface_top_block=.Gravel,
        surface_block=.Gravel,
        flooded_surface_block=.Gravel,
    },
    .{
        name="Frozen Ocean",
        color=.{ 0.51, 0.84, 1, 1},
        temperature=0,
        downfall=0.5,
        surface_top_block=.Gravel,
        surface_block=.Gravel,
        flooded_surface_block=.Gravel,
    },
    .{
        name="Deep Frozen Ocean",
        color=.{ 0.03, 0.27, 0.62, 1},
        temperature=0,
        downfall=0.5,
        surface_top_block=.Gravel,
        surface_block=.Gravel,
        flooded_surface_block=.Gravel,
    },
    .{
        name="River",
        color=.{ 0.17, 0.45, 0.97, 1},
        temperature=0.5,
        downfall=0.5,
        surface_top_block=.Sand,
        surface_block=.Sand,
        flooded_surface_block=.Sand,
    },
    .{
        name="Frozen River",
        color=.{ 0.55, 0.83, 0.99, 1},
        temperature=0,
        downfall=0.5,
        surface_top_block=.Sand,
        surface_block=.Sand,
        flooded_surface_block=.Sand,
    },
    .{
        name="Stony Shore",
        color=.{ 0.49, 0.49, 0.49, 1},
        temperature=0.2,
        downfall=0.3,
        surface_top_block=.Stone,
        surface_block=.Stone,
        flooded_surface_block=.Gravel,
    },
    .{
        name="Beach",
        color=.{ 1, 0.99, 0.6, 1},
        temperature=0.8,
        downfall=0.4,
        surface_top_block=.Sand,
        surface_block=.Sand,
        flooded_surface_block=.Sand,
    },
    .{
        name="Snowy Beach",
        color=.{ 1, 0.93, 0.78, 1},
        temperature=0,
        downfall=0.3,
        surface_top_block=.Sand,
        surface_block=.Sand,
        flooded_surface_block=.Sand,
    },
    .{
        name="Plain",
        color=.{ 0.58, 0.9, 0.35, 1},
        temperature=0.8,
        downfall=0.4,
        surface_top_block=.Grass,
        surface_block=.Dirt,
        flooded_surface_block=.Gravel,
    },
    .{
        name="Snowy Plain",
        color=.{ 0.99, 1, 0.95, 1},
        temperature=0,
        downfall=0.5,
        surface_top_block=.Snowy_Grass,
        surface_block=.Dirt,
        flooded_surface_block=.Gravel,
    },
    .{
        name="Desert",
        color=.{ 0.99, 0.89, 0.17, 1},
        temperature=2,
        downfall=0,
        has_precipitations=false,
        surface_top_block=.Sand,
        surface_block=.Sand,
        flooded_surface_block=.Sand,
    },
    .{
        name="Savanna",
        color=.{ 0.97, 0.88, 0.46, 1},
        temperature=1.2,
        downfall=0,
        has_precipitations=false,
        surface_top_block=.Grass,
        surface_block=.Dirt,
        flooded_surface_block=.Gravel,
    },
    .{
        name="Forest",
        color=.{ 0.23, 0.61, 0.2, 1},
        temperature=0.7,
        downfall=0.8,
        surface_top_block=.Grass,
        surface_block=.Dirt,
        flooded_surface_block=.Gravel,
    },
    .{
        name="Birch Forest",
        color=.{ 0.79, 0.94, 0.48, 1},
        temperature=0.6,
        downfall=0.6,
        surface_top_block=.Grass,
        surface_block=.Dirt,
        flooded_surface_block=.Gravel,
    },
    .{
        name="Taiga",
        color=.{ 0.35, 0.58, 0.25, 1},
        temperature=0.25,
        downfall=0.8,
        surface_top_block=.Grass,
        surface_block=.Dirt,
        flooded_surface_block=.Gravel,
    },
    .{
        name="Dark Forest",
        color=.{ 0.17, 0.38, 0.14, 1},
        temperature=0.7,
        downfall=0.8,
        surface_top_block=.Grass,
        surface_block=.Dirt,
        flooded_surface_block=.Gravel,
    },
    .{
        name="Jungle",
        color=.{ 0.54, 0.74, 0.17, 1},
        temperature=0.95,
        downfall=0.9,
        surface_top_block=.Grass,
        surface_block=.Dirt,
        flooded_surface_block=.Gravel,
    },
    .{
        name="Swamp",
        color=.{ 0.39, 0.45, 0.07, 1},
        temperature=0.8,
        downfall=0.9,
        surface_top_block=.Grass,
        surface_block=.Dirt,
        flooded_surface_block=.Gravel,
    },
    .{
        name="Badland",
        color=.{ 1, 0.52, 0.16, 1},
        temperature=2,
        downfall=0,
        has_precipitations=false,
        surface_top_block=.Red_Sand,
        surface_block=.Red_Sand,
        flooded_surface_block=.Red_Sand,
    },
    .{
        name="Snowy Peaks",
        color=.{ 1, 1, 1, 1},
        temperature=-0.5,
        downfall=0.9,
        surface_top_block=.Snowy_Grass,
        surface_block=.Dirt,
        flooded_surface_block=.Stone,
    },
    .{
        name="Frozen Peaks",
        color=.{ 0.82, 0.96, 1, 1},
        temperature=-0.7,
        downfall=0.9,
        surface_top_block=.Snow,
        surface_block=.Snow,
        flooded_surface_block=.Stone,
    },
    .{
        name="Stony Peaks",
        color=.{ 0.83, 0.83, 0.83, 1},
        temperature=1.0,
        downfall=0.3,
        surface_top_block=.Stone,
        surface_block=.Stone,
        flooded_surface_block=.Stone,
    },
    .{
        name="Mid Island",
        color=.{ 0.95, 0.76, 1, 1},
        temperature=0.9,
        downfall=1.0,
        surface_top_block=.Sand,
        surface_block=.Sand,
        flooded_surface_block=.Sand,
    },
];

#insert -> string
{
    #import "String_Builder";

    builder : StringBuilder;
    StringBuilderAppendLine (*builder, "BiomeID :: enum u8\n{{");

    for Biomes
    {
        StringBuilderAppend (*builder, "    ");
        for i : 0..it.name.count - 1
        {
            if it.name[i] == #char " "
                StringBuilderAppendByte (*builder, #char "_");
            else
                StringBuilderAppendByte (*builder, it.name[i]);
        }
        StringBuilderAppendLine (*builder, ";");
    }

    StringBuilderAppendLine (*builder, "    Count;\n}");

    return StringBuilderBuild (*builder);
};

ContinentalnessValue :: enum
{
    Mid_Island;
    Deep_Ocean;
    Ocean;
    Coast;
    Near_Inland;
    Mid_Inland;
    Far_Inland;
}

PeaksAndValleysValue :: enum
{
    Valleys;
    Low_Slice;
    Mid_Slice;
    High_Slice;
    Peaks;
}

BiomeParam :: enum
{
    Temperature;
    Humidity;
    Continentalness;
    Erosion;
    Weirdness;
    Peaks_And_Valleys;

    Count;
}

BiomeValues :: struct
{
    biome_id : BiomeID;

    t, h, c, e, w, pv : s8;

    #place t;
    temperature : s8;
    humidity : s8;
    continentalness : s8;
    erosion : s8;
    weirdness : s8;
    peaks_and_valleys : s8;

    #place t;
    params : [BiomeParam.Count]s8;
}

CalculateBiomeValuesFromTerrainParams :: inline (terrain_params : [TerrainParam.Count]float) -> BiomeValues #must
{
    GetIntervalValue :: (val : float, $intervals : [$N]float) -> s8 #expand
    {
        for intervals
        {
            if val < it
                return cast (s8) it_index;
        }

        return N;
    }

    Temperature_Intervals :: float.[-0.45, -0.15, 0.2, 0.55];
    Humidity_Intervals :: float.[-0.35, -0.1, 0.1, 0.3];
    Continentalness_Intervals :: float.[-1.05, -0.455, -0.19, -0.11, -0.03, 0.3];
    Erosion_Intervals :: float.[-0.78, -0.375, -0.2225, 0.05, 0.45, 0.55];
    Peaks_And_Valleys_Intervals :: float.[-0.85, -0.6, 0.2, 0.7];

    result : BiomeValues = ---;
    result.temperature = GetIntervalValue (xx terrain_params[TerrainParam.Temperature], Temperature_Intervals);
    result.humidity = GetIntervalValue (xx terrain_params[TerrainParam.Humidity], Humidity_Intervals);
    result.continentalness = GetIntervalValue (xx terrain_params[TerrainParam.Continentalness], Continentalness_Intervals);
    result.erosion = GetIntervalValue (xx terrain_params[TerrainParam.Erosion], Erosion_Intervals);
    result.weirdness = cast (s8) Sign (terrain_params[TerrainParam.Weirdness]);
    result.peaks_and_valleys = GetIntervalValue (xx terrain_params[TerrainParam.Ridges], Peaks_And_Valleys_Intervals);
    result.biome_id = GetBiome (result.params);

    return result;
}

GetBiome :: (params : [BiomeParam.Count]s8) -> BiomeID #must
{
    t, h, e, w := params[0], params[1], params[3], params[4];
    c := cast (ContinentalnessValue) params[2];
    pv := cast (PeaksAndValleysValue) params[5];

    if #complete c ==
    {
    case .Mid_Island; return .Mid_Island;
    case .Ocean;
        if t ==
        {
        case 0; return .Frozen_Ocean;
        case 1; return .Cold_Ocean;
        case 2; return .Ocean;
        case;   return .Warm_Ocean;
        }

    case .Deep_Ocean;
        if t ==
        {
        case 0; return .Deep_Frozen_Ocean;
        case 1; return .Deep_Cold_Ocean;
        case;   return .Deep_Ocean;
        }

    case .Coast;
        return GetCoastBiome (params);

    case .Near_Inland;
        return GetNearInlandBiome (params);

    case .Mid_Inland;
        return GetMidOrFarInlandBiome (params);

    case .Far_Inland;
        return GetMidOrFarInlandBiome (params);
    }
}

GetCoastBiome :: (params : [BiomeParam.Count]s8) -> BiomeID #must
{
    t, h, e, w := params[0], params[1], params[3], params[4];
    c := cast (ContinentalnessValue) params[2];
    pv := cast (PeaksAndValleysValue) params[5];

    if pv ==
    {
    case .Valleys; return ifx t == 0 then .Frozen_River else .River;
    case .Low_Slice;
        if e < 3
            return .Stony_Shore;
        else if e < 5
            return GetBeachBiome (params);
        else if e == 5
            return ifx t < 2 || h == 4 then GetMiddleBiome (params) else .Savanna;
        else
            return GetBeachBiome (params);

    case .Mid_Slice;
        if e < 3
            return .Stony_Shore;
        else if e == 5
            return ifx t < 2 || h == 4 then GetMiddleBiome (params) else .Savanna;
        else
            return GetMiddleBiome (params);

    case .High_Slice;
        if e == 5 && t > 1 && h < 4
            return .Savanna;
        else
            return GetMiddleBiome (params);

    case .Peaks;
        if e == 0
        {
            if t == 0
                return .Frozen_Peaks;
            else if t < 3
                return .Snowy_Peaks;
            else if t == 3
                return .Stony_Peaks;
            else
                return GetBadlandBiome (params);
        }
        else if e == 1
        {
            if t < 4
                return GetMiddleBiome (params);
            else
                return GetBadlandBiome (params);
        }
        else if e == 5
            return .Savanna;
        else
            return GetMiddleBiome (params);
    }

    return .Void;
}

GetNearInlandBiome :: (params : [BiomeParam.Count]s8) -> BiomeID #must
{
    t, h, e, w := params[0], params[1], params[3], params[4];
    c := cast (ContinentalnessValue) params[2];
    pv := cast (PeaksAndValleysValue) params[5];

    if #complete pv ==
    {
    case .Valleys;
        if e < 6
            return ifx t == 0 then .Frozen_River else .River;
        else
            return ifx t == 0 then .Frozen_River else .Swamp;

    case .Low_Slice;
        if e < 2
            return ifx t < 4 then GetMiddleBiome (params) else GetBadlandBiome (params);
        else if e < 5
            return GetMiddleBiome (params);
        else if t < 2 || h == 4
            return GetMiddleBiome (params);
        else
            return .Savanna;

    case .Mid_Slice;
        if e == 0
            return GetMiddleBiome (params);
        else if e == 1
            return ifx t == 4 then GetBadlandBiome (params) else GetMiddleBiome (params);
        else if e < 5
            return GetMiddleBiome (params);
        else if e == 5
            return ifx t < 2 || h == 4 then GetMiddleBiome (params) else .Savanna;
        else
            return ifx t == 0 then GetMiddleBiome (params) else .Swamp;

    case .High_Slice;
        if e == 0
            return GetMiddleBiome (params);
        else if e == 1
            return ifx t == 4 then GetBadlandBiome (params) else GetMiddleBiome (params);
        else if e < 5
            return GetMiddleBiome (params);
        else if e == 5
            return ifx t < 2 || h == 4 then GetMiddleBiome (params) else .Savanna;
        else
            return GetMiddleBiome (params);

    case .Peaks;
        if e == 0
        {
            if t == 0
                return .Frozen_Peaks;
            else if t < 3
                return .Snowy_Peaks;
            else if t == 3
                return .Stony_Peaks;
            else
                return GetBadlandBiome (params);
        }
        else if e == 1
        {
            if t < 4
                return GetMiddleBiome (params);
            else
                return GetBadlandBiome (params);
        }
        else if e == 5
            return .Savanna;
        else
            return GetMiddleBiome (params);
    }
}

GetMidOrFarInlandBiome :: (params : [BiomeParam.Count]s8) -> BiomeID #must
{
    t, h, e, w := params[0], params[1], params[3], params[4];
    c := cast (ContinentalnessValue) params[2];
    pv := cast (PeaksAndValleysValue) params[5];

    if #complete pv ==
    {
    case .Valleys;
        if e < 2
            return ifx t == 4 then GetBadlandBiome (params) else GetMiddleBiome (params);
        else if e < 6
            return ifx t == 0 then .Frozen_River else .River;
        else
            return ifx t == 0 then .Frozen_River else .Swamp;

    case .Low_Slice;
        if e < 4
            return ifx t < 4 then GetMiddleBiome (params) else GetBadlandBiome (params);
        else if e < 6
            return GetMiddleBiome (params);
        else
            return ifx t == 0 then GetMiddleBiome (params) else .Swamp;

    case .Mid_Slice;
        if e == 0
            return GetMiddleBiome (params);
        else if e == 1
            return ifx t == 4 then GetBadlandBiome (params) else GetMiddleBiome (params);
        else if e < 5
            return GetMiddleBiome (params);
        else if e == 5
            return ifx t < 2 || h == 4 then GetMiddleBiome (params) else .Savanna;
        else
            return ifx t == 0 then GetMiddleBiome (params) else .Swamp;

    case .High_Slice;
        if e == 3 || e == 4
            return ifx t == 4 then GetBadlandBiome (params) else GetMiddleBiome (params);
        else
            return GetMiddleBiome (params);

    case .Peaks;
        if e < 2
        {
            if t == 0
                return .Frozen_Peaks;
            else if t < 3
                return .Snowy_Peaks;
            else if t == 3
                return .Stony_Peaks;
            else
                return GetBadlandBiome (params);
        }
        else if e == 3 || e == 4
            return ifx t == 4 then GetBadlandBiome (params) else GetMiddleBiome (params);
        else
            return GetMiddleBiome (params);
    }
}

GetBeachBiome :: inline (params : [BiomeParam.Count]s8) -> BiomeID #must
{
    t := params[0];

    if t == 0
        return .Snowy_Beach;
    else if t < 4
        return .Beach;
    else
        return .Desert;
}

GetBadlandBiome :: inline (params : [BiomeParam.Count]s8) -> BiomeID #must
{
    return .Badland;
}

GetMiddleBiome :: (params : [BiomeParam.Count]s8) -> BiomeID #must
{
    t, h, e, w := params[0], params[1], params[3], params[4];
    c := cast (ContinentalnessValue) params[2];
    pv := cast (PeaksAndValleysValue) params[5];

    if t == 0
    {
        return .Snowy_Plain;
    }
    else if t == 1
    {
        if h < 2
            return .Plain;
        else if h == 2
            return .Forest;
        else
            return .Taiga;
    }
    else if t == 2
    {
        if h < 2
            return .Plain;
        else if h == 2
            return .Forest;
        else if h == 3
            return .Birch_Forest;
        else
            return .Dark_Forest;
    }
    else if t == 3
    {
        if h < 2
            return .Savanna;
        else if h == 2
            return .Forest;
        else
            return .Jungle;
    }
    else
    {
        return .Desert;
    }
}
