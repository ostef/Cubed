Biome :: struct
{
    name : string;
    color := Vec4f.{0,0,0,1};
    temperature : float;
    downfall : float;
    has_precipitations := true;
}

Biomes := Biome.[
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
    },
    .{
        name="Deep Ocean",
        color=.{ 0.1, 0.14, 0.62, 1},
        temperature=0.5,
        downfall=0.5,
    },
    .{
        name="Warm Ocean",
        color=.{ 0.06, 0.16, 0.95, 1},
        temperature=0.5,
        downfall=0.5,
    },
    .{
        name="Cold Ocean",
        color=.{ 0.16, 0.58, 0.98, 1},
        temperature=0.5,
        downfall=0.5,
    },
    .{
        name="Deep Cold Ocean",
        color=.{ 0.03, 0.29, 0.53, 1},
        temperature=0.5,
        downfall=0.5,
    },
    .{
        name="Frozen Ocean",
        color=.{ 0.51, 0.84, 1, 1},
        temperature=0,
        downfall=0.5,
    },
    .{
        name="Deep Frozen Ocean",
        color=.{ 0.03, 0.27, 0.62, 1},
        temperature=0,
        downfall=0.5,
    },
    .{
        name="River",
        color=.{ 0.17, 0.45, 0.97, 1},
        temperature=0.5,
        downfall=0.5,
    },
    .{
        name="Frozen River",
        color=.{ 0.55, 0.83, 0.99, 1},
        temperature=0,
        downfall=0.5,
    },
    .{
        name="Stony Shore",
        color=.{ 0.49, 0.49, 0.49, 1},
        temperature=0.2,
        downfall=0.3,
    },
    .{
        name="Beach",
        color=.{ 1, 0.99, 0.6, 1},
        temperature=0.8,
        downfall=0.4,
    },
    .{
        name="Snowy Beach",
        color=.{ 1, 0.93, 0.78, 1},
        temperature=0,
        downfall=0.3,
    },
    .{
        name="Plain",
        color=.{ 0.58, 0.9, 0.35, 1},
        temperature=0.8,
        downfall=0.4,
    },
    .{
        name="Snowy Plain",
        color=.{ 0.99, 1, 0.95, 1},
        temperature=0,
        downfall=0.5,
    },
    .{
        name="Desert",
        color=.{ 0.99, 0.89, 0.17, 1},
        temperature=2,
        downfall=0,
        has_precipitations=false,
    },
    .{
        name="Savanna",
        color=.{ 0.97, 0.88, 0.46, 1},
        temperature=1.2,
        downfall=0,
        has_precipitations=false,
    },
    .{
        name="Forest",
        color=.{ 0.23, 0.61, 0.2, 1},
        temperature=0.7,
        downfall=0.8,
    },
    .{
        name="Birch Forest",
        color=.{ 0.79, 0.94, 0.48, 1},
        temperature=0.6,
        downfall=0.6,
    },
    .{
        name="Taiga",
        color=.{ 0.35, 0.58, 0.25, 1},
        temperature=0.25,
        downfall=0.8,
    },
    .{
        name="Dark Forest",
        color=.{ 0.17, 0.38, 0.14, 1},
        temperature=0.7,
        downfall=0.8,
    },
    .{
        name="Jungle",
        color=.{ 0.54, 0.74, 0.17, 1},
        temperature=0.95,
        downfall=0.9,
    },
    .{
        name="Swamp",
        color=.{ 0.39, 0.45, 0.07, 1},
        temperature=0.8,
        downfall=0.9,
    },
    .{
        name="Badland",
        color=.{ 1, 0.52, 0.16, 1},
        temperature=2,
        downfall=0,
        has_precipitations=false,
    },
    .{
        name="Snowy Peaks",
        color=.{ 1, 1, 1, 1},
        temperature=-0.5,
        downfall=0.9,
    },
    .{
        name="Frozen Peaks",
        color=.{ 0.82, 0.96, 1, 1},
        temperature=-0.7,
        downfall=0.9,
    },
    .{
        name="Stony Peaks",
        color=.{ 0.83, 0.83, 0.83, 1},
        temperature=1.0,
        downfall=0.3,
    },
    .{
        name="Mid Island",
        color=.{ 0.95, 0.76, 1, 1},
        temperature=0.9,
        downfall=1.0,
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
    Depth;

    Count;
}

CalculateBiomeParam :: (using generator : Generator, param : BiomeParam, x : float, z : float) -> float #must
{
    GetIntervalValue :: (val : float, $intervals : [$N]float) -> int #expand
    {
        for intervals
        {
            if val < it
                return it_index;
        }

        return N - 1;
    }

    Temperature_Intervals :: float.[-0.45, -0.15, 0.2, 0.55];
    Humidity_Intervals :: float.[-0.35, -0.1, 0.1, 0.3];
    Continentalness_Intervals :: float.[-1.05, -0.455, -0.19, -0.11, -0.03, 0.3];
    Erosion_Intervals :: float.[-0.78, -0.375, -0.2225, 0.05, 0.45, 0.55];
    Peaks_And_Valleys_Intervals :: float.[-0.85, -0.6, 0.2, 0.7];

    val := CalculateTerrainParam (generator, cast (TerrainParam) param, x, z);

    if param == .Temperature
        return xx GetIntervalValue (val, Temperature_Intervals);

    if param == .Humidity
        return xx GetIntervalValue (val, Humidity_Intervals);

    if param == .Continentalness
        return xx GetIntervalValue (val, Continentalness_Intervals);

    if param == .Erosion
        return xx GetIntervalValue (val, Erosion_Intervals);

    if param == .Peaks_And_Valleys
        return xx GetIntervalValue (val, Peaks_And_Valleys_Intervals);

    return val;
}

GetBiomeAtLocation :: (generator : Generator, x : float, z : float) -> BiomeID #must
{
    c := cast (ContinentalnessValue) CalculateBiomeParam (generator, .Continentalness, x, z);
    if #complete c ==
    {
    case .Mid_Island; return .Mid_Island;
    case .Ocean;
        t := cast (int) CalculateBiomeParam (generator, .Temperature, x, z);
        if t ==
        {
        case 0; return .Frozen_Ocean;
        case 1; return .Cold_Ocean;
        case 2; return .Ocean;
        case;   return .Warm_Ocean;
        }

    case .Deep_Ocean;
        t := cast (int) CalculateBiomeParam (generator, .Temperature, x, z);
        if t ==
        {
        case 0; return .Deep_Frozen_Ocean;
        case 1; return .Deep_Cold_Ocean;
        case;   return .Deep_Ocean;
        }

    case .Coast;
        return GetCoastBiome (generator, x, z);

    case .Near_Inland;
        return GetNearInlandBiome (generator, x, z);

    case .Mid_Inland;
        return GetMidOrFarInlandBiome (generator, x, z);

    case .Far_Inland;
        return GetMidOrFarInlandBiome (generator, x, z);
    }
}

GetCoastBiome :: (generator : Generator, x : float, z : float) -> BiomeID #must
{
    t := cast (int) CalculateBiomeParam (generator, .Temperature, x, z);
    pv := cast (PeaksAndValleysValue) CalculateBiomeParam (generator, .Peaks_And_Valleys, x, z);
    e := cast (int) CalculateBiomeParam (generator, .Erosion, x, z);
    if pv ==
    {
    case .Valleys; return ifx t == 0 then .Frozen_River else .River;
    case .Low_Slice;
        h := cast (int) CalculateBiomeParam (generator, .Humidity, x, z);
        if e < 3
            return .Stony_Shore;
        else if e < 5
            return GetBeachBiome (generator, t, x, z);
        else if e == 5
            return ifx t < 2 || h == 4 then GetMiddleBiome (generator, t, h, x, z) else .Savanna;
        else
            return GetBeachBiome (generator, t, x, z);

    case .Mid_Slice;
        h := cast (int) CalculateBiomeParam (generator, .Humidity, x, z);
        if e < 3
            return .Stony_Shore;
        else if e == 5
            return ifx t < 2 || h == 4 then GetMiddleBiome (generator, t, h, x, z) else .Savanna;
        else
            return GetMiddleBiome (generator, t, h, x, z);

    case .High_Slice;
        h := cast (int) CalculateBiomeParam (generator, .Humidity, x, z);
        if e == 5 && t > 1 && h < 4
            return .Savanna;
        else
            return GetMiddleBiome (generator, t, h, x, z);

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
                return GetBadlandBiome (generator, x, z);
        }
        else if e == 1
        {
            if t < 4
                return GetMiddleBiome (generator, t, xx CalculateBiomeParam (generator, .Humidity, x, z), x, z);
            else
                return GetBadlandBiome (generator, x, z);
        }
        else if e == 5
            return .Savanna;
        else
            return GetMiddleBiome (generator, t, xx CalculateBiomeParam (generator, .Humidity, x, z), x, z);
    }

    return .Void;
}

GetNearInlandBiome :: (generator : Generator, x : float, z : float) -> BiomeID #must
{
    t := cast (int) CalculateBiomeParam (generator, .Temperature, x, z);
    pv := cast (PeaksAndValleysValue) CalculateBiomeParam (generator, .Peaks_And_Valleys, x, z);
    e := cast (int) CalculateBiomeParam (generator, .Erosion, x, z);
    if #complete pv ==
    {
    case .Valleys;
        if e < 6
            return ifx t == 0 then .Frozen_River else .River;
        else
            return ifx t == 0 then .Frozen_River else .Swamp;

    case .Low_Slice;
        h := cast (int) CalculateBiomeParam (generator, .Humidity, x, z);
        if e < 2
            return ifx t < 4 then GetMiddleBiome (generator, t, h, x, z) else GetBadlandBiome (generator, x, z);
        else if e < 5
            return GetMiddleBiome (generator, t, h, x, z);
        else if t < 2 || h == 4
            return GetMiddleBiome (generator, t, h, x, z);
        else
            return .Savanna;

    case .Mid_Slice;
        h := cast (int) CalculateBiomeParam (generator, .Humidity, x, z);
        if e == 0
            return GetMiddleBiome (generator, t, h, x, z);
        else if e == 1
            return ifx t == 4 then GetBadlandBiome (generator, x, z) else GetMiddleBiome (generator, t, h, x, z);
        else if e < 5
            return GetMiddleBiome (generator, t, h, x, z);
        else if e == 5
            return ifx t < 2 || h == 4 then GetMiddleBiome (generator, t, h, x, z) else .Savanna;
        else
            return ifx t == 0 then GetMiddleBiome (generator, t, h, x, z) else .Swamp;

    case .High_Slice;
        h := cast (int) CalculateBiomeParam (generator, .Humidity, x, z);
        if e == 0
            return GetMiddleBiome (generator, t, h, x, z);
        else if e == 1
            return ifx t == 4 then GetBadlandBiome (generator, x, z) else GetMiddleBiome (generator, t, h, x, z);
        else if e < 5
            return GetMiddleBiome (generator, t, h, x, z);
        else if e == 5
            return ifx t < 2 || h == 4 then GetMiddleBiome (generator, t, h, x, z) else .Savanna;
        else
            return GetMiddleBiome (generator, t, h, x, z);

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
                return GetBadlandBiome (generator, x, z);
        }
        else if e == 1
        {
            if t < 4
                return GetMiddleBiome (generator, t, xx CalculateBiomeParam (generator, .Humidity, x, z), x, z);
            else
                return GetBadlandBiome (generator, x, z);
        }
        else if e == 5
            return .Savanna;
        else
            return GetMiddleBiome (generator, t, xx CalculateBiomeParam (generator, .Humidity, x, z), x, z);
    }
}

GetMidOrFarInlandBiome :: (generator : Generator, x : float, z : float) -> BiomeID #must
{
    t := cast (int) CalculateBiomeParam (generator, .Temperature, x, z);
    pv := cast (PeaksAndValleysValue) CalculateBiomeParam (generator, .Peaks_And_Valleys, x, z);
    e := cast (int) CalculateBiomeParam (generator, .Erosion, x, z);
    if #complete pv ==
    {
    case .Valleys;
        if e < 2
            return ifx t == 4 then GetBadlandBiome (generator, x, z) else GetMiddleBiome (generator, t, xx CalculateBiomeParam (generator, .Humidity, x, z), x, z);
        else if e < 6
            return ifx t == 0 then .Frozen_River else .River;
        else
            return ifx t == 0 then .Frozen_River else .Swamp;

    case .Low_Slice;
        if e < 4
            return ifx t < 4 then GetMiddleBiome (generator, t, xx CalculateBiomeParam (generator, .Humidity, x, z), x, z) else GetBadlandBiome (generator, x, z);
        else if e < 6
            return GetMiddleBiome (generator, t, xx CalculateBiomeParam (generator, .Humidity, x, z), x, z);
        else
            return ifx t == 0 then GetMiddleBiome (generator, t, xx CalculateBiomeParam (generator, .Humidity, x, z), x, z) else .Swamp;

    case .Mid_Slice;
        h := cast (int) CalculateBiomeParam (generator, .Humidity, x, z);
        if e == 0
            return GetMiddleBiome (generator, t, h, x, z);
        else if e == 1
            return ifx t == 4 then GetBadlandBiome (generator, x, z) else GetMiddleBiome (generator, t, h, x, z);
        else if e < 5
            return GetMiddleBiome (generator, t, h, x, z);
        else if e == 5
            return ifx t < 2 || h == 4 then GetMiddleBiome (generator, t, h, x, z) else .Savanna;
        else
            return ifx t == 0 then GetMiddleBiome (generator, t, h, x, z) else .Swamp;

    case .High_Slice;
        if e == 3 || e == 4
            return ifx t == 4 then GetBadlandBiome (generator, x, z) else GetMiddleBiome (generator, t, xx CalculateBiomeParam (generator, .Humidity, x, z), x, z);
        else
            return GetMiddleBiome (generator, t, xx CalculateBiomeParam (generator, .Humidity, x, z), x, z);

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
                return GetBadlandBiome (generator, x, z);
        }
        else if e == 3 || e == 4
            return ifx t == 4 then GetBadlandBiome (generator, x, z) else GetMiddleBiome (generator, t, xx CalculateBiomeParam (generator, .Humidity, x, z), x, z);
        else
            return GetMiddleBiome (generator, t, xx CalculateBiomeParam (generator, .Humidity, x, z), x, z);
    }
}

GetBeachBiome :: inline (generator : Generator, t : int, x : float, z : float) -> BiomeID #must
{
    if t == 0
        return .Snowy_Beach;
    else if t < 4
        return .Beach;
    else
        return .Desert;
}

GetBadlandBiome :: inline (generator : Generator, x : float, z : float) -> BiomeID #must
{
    return .Badland;
}

GetMiddleBiome :: (generator: Generator, t : int, h : int, x : float, z : float) -> BiomeID #must
{
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
