// This is used as a filter for intersection tests
BlockFlags :: struct
{
    Size :: #run cast (int) Ceil (BlockID.Count / 8.0);

    bytes : [Size]u8;
}

Block_Flags_Solid :: #run () -> BlockFlags
{
    flags : BlockFlags;
    memset (*flags.bytes, 0xff, flags.Size);
    RemoveBlockFlag (*flags, .Water);
    RemoveBlockFlag (*flags, .Air);
    RemoveBlockFlag (*flags, .Grass_Foliage);

    return flags;
} ();

MakeBlockFlags :: inline (blocks : ..BlockID) -> BlockFlags #must
{
    result : BlockFlags;
    SetBlockFlags (*result, ..blocks);

    return result;
}

BlockFlagIsSet :: inline (using flags : BlockFlags, block : BlockID) -> bool #must
{
    byte_index := cast (int) block / 8;
    bit_index := cast (int) block % 8;

    return (bytes[byte_index] & (cast (u8) 0x1 << bit_index)) != 0;
}

SetBlockFlag :: inline (using flags : *BlockFlags, block : BlockID)
{
    byte_index := cast (int) block / 8;
    bit_index := cast (int) block % 8;
    bytes[byte_index] |= cast (u8) 0x1 << bit_index;
}

SetBlockFlags :: inline (using flags : *BlockFlags, blocks : ..BlockID)
{
    for block : blocks
    {
        byte_index := cast (int) block / 8;
        bit_index := cast (int) block % 8;
        bytes[byte_index] |= cast (u8) 0x1 << bit_index;
    }
}

RemoveBlockFlag :: inline (using flags : *BlockFlags, block : BlockID)
{
    byte_index := cast (int) block / 8;
    bit_index := cast (int) block % 8;
    bytes[byte_index] &= ~(cast (u8) 0x1 << bit_index);
}

RemoveBlockFlags :: inline (using flags : *BlockFlags, blocks : ..BlockID)
{
    for block : blocks
    {
        byte_index := cast (int) block / 8;
        bit_index := cast (int) block % 8;
        bytes[byte_index] &= ~(cast (u8) 0x1 << bit_index);
    }
}

AABB :: struct
{
    min : Vec3f;
    max : Vec3f;
}

Ray :: struct
{
    origin : Vec3f;
    direction : Vec3f;
    length : float;
}

HitResult :: struct
{
    hit : bool;
    normal : Vec3f;
    position : Vec3f;
    distance : float;

    chunk_x, chunk_z : s64;
    chunk : *Chunk;
    block_x, block_y, block_z : s64;
    block : Block;
    block_face : BlockFace;
}

MakeAABBPositionHalfSize :: inline (position : Vec3f, half_size : Vec3f) -> AABB #must
{
    return .{
        position - half_size,
        position + half_size
    };
}

AABBCenter :: inline (using aabb : AABB) -> Vec3f #must
{
    return (min + max) * 0.5;
}

AABBSize :: inline (using aabb : AABB) -> Vec3f #must
{
    return max - min;
}

AABBHalfSize :: inline (using aabb : AABB) -> Vec3f #must
{
    return (max - min) * 0.5;
}

PointIsInsideAABB :: inline (point : Vec3f, aabb : AABB) -> bool #must
{
    return
        point.x >= aabb.min.x &&
        point.x <= aabb.max.x &&
        point.y >= aabb.min.y &&
        point.y <= aabb.max.y &&
        point.z >= aabb.min.z &&
        point.z <= aabb.max.z;
}

CalculateAABBPenetration :: (point_inside_aabb : Vec3f, aabb : AABB) -> Vec3f #must
{
    center := AABBCenter (aabb);
    min := aabb.min - center;
    max := aabb.max - center;
    point := point_inside_aabb - center;

    dist := min.x - point.x;
    abs_dist := Abs (dist);
    min_dist := abs_dist;
    result := Vec3f.{dist, 0, 0};

    dist = max.x - point.x;
    abs_dist = Abs (dist);
    if abs_dist < min_dist
    {
        min_dist = abs_dist;
        result = .{dist, 0, 0};
    }

    dist = min.y - point.y;
    abs_dist = Abs (dist);
    if abs_dist < min_dist
    {
        min_dist = abs_dist;
        result = .{0, dist, 0};
    }

    dist = max.y - point.y;
    abs_dist = Abs (dist);
    if abs_dist < min_dist
    {
        min_dist = abs_dist;
        result = .{0, dist, 0};
    }

    dist = min.z - point.z;
    abs_dist = Abs (dist);
    if abs_dist < min_dist
    {
        min_dist = abs_dist;
        result = .{0, 0, dist};
    }

    dist = max.z - point.z;
    abs_dist = Abs (dist);
    if abs_dist < min_dist
    {
        min_dist = abs_dist;
        result = .{0, 0, dist};
    }

    return result;
}

ClosestPointOnAABB :: inline (point : Vec3f, using aabb : AABB) -> Vec3f #must
{
    if PointIsInsideAABB (point, aabb)
        return point + CalculateAABBPenetration (point, aabb);

    return Linalg.clamp (point, aabb.min, aabb.max);
}

AABBIntersectsAABB :: inline (a : AABB, b : AABB) -> bool #must
{
    return
        a.min.x <= b.max.x &&
        a.max.x >= b.min.x &&
        a.min.y <= b.max.y &&
        a.max.y >= b.min.y &&
        a.min.z <= b.max.z &&
        a.max.z >= b.min.z;
}

SweptAABBIntersectsAABB :: inline (a : AABB, b : AABB, direction : Vec3f, length : float, $return_tnear_when_inside := true) -> HitResult #must
{
    b_padded := MakeAABBPositionHalfSize (AABBCenter (b), AABBHalfSize (a) + AABBHalfSize (b));

    ray := Ray.{ origin = AABBCenter (a), direction = direction, length = length };

    return RayIntersectsAABB (ray, b_padded, return_tnear_when_inside);
}

// return_tnear_when_inside will always return a hit with a distance of t_near when the ray
// origin is inside of the AABB. This is useful for collision resolution, to push entities outside
// of solid objects in the opposite direction they're going
RayIntersectsAABB :: (ray : Ray, aabb : AABB, $return_tnear_when_inside := true) -> HitResult #must, t_near : float, t_far : float
{
    if ApproxZero (ray.direction, 0.00001)
        return .{}, 0, 0;

    result : HitResult;

    inv_dir := Vec3f.{1 / ray.direction.x, 1 / ray.direction.y, 1 / ray.direction.z};
    t1 := Scale (aabb.min - ray.origin, inv_dir);
    t2 := Scale (aabb.max - ray.origin, inv_dir);

    t_min := Linalg.min (t1, t2);
    t_max := Linalg.max (t1, t2);

    t_near := Max (Max (t_min.x, t_min.y), t_min.z);
    t_far  := Min (Min (t_max.x, t_max.y), t_max.z);
#if return_tnear_when_inside
    intersects := (t_far > t_near && t_near >= 0 && t_near < ray.length) || (t_near < 0 && t_far > 0);
else
    intersects := t_far > t_near && t_near >= 0 && t_near < ray.length;

    if intersects
    {
        result.hit = true;
        result.position = ray.origin + ray.direction * t_near;
        result.distance = t_near;
        result.normal = .{
            cast (float) (t_near == t_min.x || t_near == t_max.x) * Sign (-inv_dir.x),
            cast (float) (t_near == t_min.y || t_near == t_max.y) * Sign (-inv_dir.y),
            cast (float) (t_near == t_min.z || t_near == t_max.z) * Sign (-inv_dir.z)
        };
    }

    return result, t_near, t_far;
}

RayIntersectsWorld :: (world : *World, ray : Ray, filter := Block_Flags_Solid) -> HitResult #must
{
    min_x, max_x := MinMax (ray.origin.x, ray.origin.x + ray.direction.x * ray.length);
    min_y, max_y := MinMax (ray.origin.y, ray.origin.y + ray.direction.y * ray.length);
    min_z, max_z := MinMax (ray.origin.z, ray.origin.z + ray.direction.z * ray.length);

    min_x = Floor (min_x);
    min_y = Floor (min_y);
    min_z = Floor (min_z);

    max_x = Ceil (max_x);
    max_y = Ceil (max_y);
    max_z = Ceil (max_z);

    chunk_x, chunk_z := ChunkPositionFromWorldPosition (cast (int) min_x, cast (int)  min_z);
    chunk := WorldGetChunk (world, chunk_x, chunk_z);

    closest_hit : HitResult;
    closest_hit.distance = Math.FLOAT32_MAX;
    for y : cast (int) min_y..cast (int) max_y
    {
        for z : cast (int) min_z..cast (int) max_z
        {
            for x : cast (int) min_x..cast (int) max_x
            {
                curr_chunk_x, curr_chunk_z := ChunkPositionFromWorldPosition (x, z);
                if chunk_x != curr_chunk_x || chunk_z != curr_chunk_z
                {
                    chunk_x = curr_chunk_x;
                    chunk_z = curr_chunk_z;
                    chunk = WorldGetChunk (world, chunk_x, chunk_z);
                }

                if !chunk
                    continue;

                rel_x, rel_z := ChunkAbsoluteToRelativeCoordinates (chunk_x, chunk_z, x, z);

                block := ChunkGetBlockInChunk (chunk, rel_x, y, rel_z);
                if !BlockFlagIsSet (filter, block)
                    continue;

                block_aabb := BlockAABB (block, x, y, z);
                result := RayIntersectsAABB (ray, block_aabb);
                if result.hit && result.distance < closest_hit.distance
                {
                    closest_hit = result;
                    closest_hit.chunk = chunk;
                    closest_hit.chunk_x = chunk_x;
                    closest_hit.chunk_z = chunk_z;
                    closest_hit.block = block;
                    closest_hit.block_x = x;
                    closest_hit.block_y = y;
                    closest_hit.block_z = z;
                }
            }
        }
    }

    if closest_hit.hit
        closest_hit.block_face = BlockFaceFromNormal (closest_hit.normal);

    return closest_hit;
}

SweptAABBIntersectsWorld :: (world : *World, aabb : AABB, direction : Vec3f, length : float, filter := Block_Flags_Solid) -> HitResult #must
{
    ProfileBlock ();

    center := AABBCenter (aabb);
    half_size := AABBHalfSize (aabb);
    min_x, max_x := MinMax (center.x, center.x + direction.x * length);
    min_y, max_y := MinMax (center.y, center.y + direction.y * length);
    min_z, max_z := MinMax (center.z, center.z + direction.z * length);

    min_x = Floor (min_x - half_size.x);
    min_y = Floor (min_y - half_size.y);
    min_z = Floor (min_z - half_size.z);

    max_x = Ceil (max_x + half_size.x);
    max_y = Ceil (max_y + half_size.y);
    max_z = Ceil (max_z + half_size.z);

    chunk_x, chunk_z := ChunkPositionFromWorldPosition (cast (int) min_x, cast (int)  min_z);
    chunk := WorldGetChunk (world, chunk_x, chunk_z);

    // This is not supposed to happen. If it does, it will provoke an infinite loop, so we debug break
    // to debug it when we'll encounter that case
    if max_x < min_x || max_y < min_y || max_z < min_z
        debug_break ();

    closest_hit : HitResult;
    closest_hit.distance = Math.FLOAT32_MAX;
    for y : cast (int) min_y..cast (int) max_y
    {
        for z : cast (int) min_z..cast (int) max_z
        {
            for x : cast (int) min_x..cast (int) max_x
            {
                curr_chunk_x, curr_chunk_z := ChunkPositionFromWorldPosition (x, z);
                if chunk_x != curr_chunk_x || chunk_z != curr_chunk_z
                {
                    chunk_x = curr_chunk_x;
                    chunk_z = curr_chunk_z;
                    chunk = WorldGetChunk (world, chunk_x, chunk_z);
                }

                if !chunk
                {
                    chunk_aabb := ChunkAABB (chunk_x, chunk_z);
                    result := SweptAABBIntersectsAABB (aabb, chunk_aabb, direction, length, return_tnear_when_inside = false);
                    if result.hit && result.distance < closest_hit.distance
                    {
                        closest_hit = result;
                        closest_hit.chunk = null;
                        closest_hit.chunk_x = chunk_x;
                        closest_hit.chunk_z = chunk_z;
                    }

                    continue;
                }

                rel_x, rel_z := ChunkAbsoluteToRelativeCoordinates (chunk_x, chunk_z, x, z);

                block := ChunkGetBlockInChunk (chunk, rel_x, y, rel_z);
                if !BlockFlagIsSet (filter, block)
                    continue;

                block_aabb := BlockAABB (block, x, y, z);
                result := SweptAABBIntersectsAABB (aabb, block_aabb, direction, length);
                if result.hit && result.distance < closest_hit.distance
                {
                    closest_hit = result;
                    closest_hit.chunk = chunk;
                    closest_hit.chunk_x = chunk_x;
                    closest_hit.chunk_z = chunk_z;
                    closest_hit.block = block;
                    closest_hit.block_x = x;
                    closest_hit.block_y = y;
                    closest_hit.block_z = z;
                }
            }
        }
    }

    if closest_hit.hit
        closest_hit.block_face = BlockFaceFromNormal (closest_hit.normal);

    return closest_hit;
}

AABBIntersectsWorld :: (world : *World, aabb : AABB, filter := Block_Flags_Solid) -> bool #must
{
    ProfileBlock ();

    min_x, max_x := Floor (aabb.min.x), Ceil (aabb.max.x);
    min_y, max_y := Floor (aabb.min.y), Ceil (aabb.max.y);
    min_z, max_z := Floor (aabb.min.z), Ceil (aabb.max.z);

    chunk_x, chunk_z := ChunkPositionFromWorldPosition (cast (int) min_x, cast (int)  min_z);
    chunk := WorldGetChunk (world, chunk_x, chunk_z);

    // This is not supposed to happen. If it does, it will provoke an infinite loop, so we debug break
    // to debug it when we'll encounter that case
    if max_x < min_x || max_y < min_y || max_z < min_z
        debug_break ();

    for y : cast (int) min_y..cast (int) max_y
    {
        for z : cast (int) min_z..cast (int) max_z
        {
            for x : cast (int) min_x..cast (int) max_x
            {
                curr_chunk_x, curr_chunk_z := ChunkPositionFromWorldPosition (x, z);
                if chunk_x != curr_chunk_x || chunk_z != curr_chunk_z
                {
                    chunk_x = curr_chunk_x;
                    chunk_z = curr_chunk_z;
                    chunk = WorldGetChunk (world, chunk_x, chunk_z);
                }

                if !chunk
                    continue;

                rel_x, rel_z := ChunkAbsoluteToRelativeCoordinates (chunk_x, chunk_z, x, z);

                block := ChunkGetBlockInChunk (chunk, rel_x, y, rel_z);
                if !BlockFlagIsSet (filter, block)
                    continue;

                block_aabb := BlockAABB (block, x, y, z);
                if AABBIntersectsAABB (aabb, block_aabb)
                    return true;
            }
        }
    }

    return false;
}

BlockFaceFromNormal :: inline (normal : Vec3f) -> BlockFace #must
{
    if ApproxEquals (normal, .{1, 0, 0}, 0.00001)
        return .East;
    else if ApproxEquals (normal, .{-1, 0, 0}, 0.00001)
        return .West;
    else if ApproxEquals (normal, .{0, 1, 0}, 0.00001)
        return .Above;
    else if ApproxEquals (normal, .{0, -1, 0}, 0.00001)
        return .Below;
    else if ApproxEquals (normal, .{0, 0, 1}, 0.00001)
        return .North;
    else if ApproxEquals (normal, .{0, 0, -1}, 0.00001)
        return .South;
    return .East;
}
