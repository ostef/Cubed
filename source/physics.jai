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

SweptAABBIntersectsAABB :: inline (a : AABB, b : AABB, direction : Vec3f, length : float) -> HitResult #must
{
    b_padded := MakeAABBPositionHalfSize (AABBCenter (b), AABBHalfSize (a) + AABBHalfSize (b));

    ray := Ray.{ origin = AABBCenter (a), direction = direction, length = length};

    return RayIntersectsAABB (ray, b_padded);
}

RayIntersectsAABB :: (ray : Ray, aabb : AABB) -> HitResult #must, t_near : float, t_far : float
{
    result : HitResult;

    inv_dir := Vec3f.{1 / ray.direction.x, 1 / ray.direction.y, 1 / ray.direction.z};
    t_min := Scale (aabb.min - ray.origin, inv_dir);
    t_max := Scale (aabb.max - ray.origin, inv_dir);

    t1 := Linalg.min (t_min, t_max);
    t2 := Linalg.max (t_min, t_max);

    t_near := Max (Max (t1.x, t1.y), t1.z);
    t_far  := Min (Min (t2.x, t2.y), t2.z);
    distance := ifx t_near < 0 then t_far else t_near;

    if distance > 0 && distance < ray.length
    {
        result.hit = true;
        result.position = ray.origin + ray.direction * distance;
        result.distance = distance;

        dist_to_center := result.position - AABBCenter (aabb);
        dist_to_sides := AABBHalfSize (aabb) - Linalg.abs (dist_to_center);

        if dist_to_sides.x < dist_to_sides.y
            result.normal.x = Sign (dist_to_center.x);
        else if dist_to_sides.y < dist_to_sides.z
            result.normal.y = Sign (dist_to_center.y);
        else
            result.normal.z = Sign (dist_to_center.z);
    }

    return result, t_near, t_far;
}

SweptAABBIntersectsWorld :: (world : *World, aabb : AABB, direction : Vec3f, length : float) -> HitResult #must
{
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

    closest_hit : HitResult;
    closest_hit.distance = Math.FLOAT32_MAX;
    for z : cast (int) min_z..cast (int) max_z
    {
        for y : cast (int) min_y..cast (int) max_y
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
                    chunk_aabb := ChunkAABB (x / Chunk_Size, z / Chunk_Size);
                    result := SweptAABBIntersectsAABB (aabb, chunk_aabb, direction, length);
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
                block_aabb := BlockAABB (x, y, z);

                block := ChunkGetBlockInChunk (chunk, rel_x, y, rel_z);
                if block.kind == .Air || block.kind == .Water
                    continue;

                result := SweptAABBIntersectsAABB (aabb, block_aabb, direction, length);
                if result.hit
                {
                    Im3d.PushColor (Im3d.Color_Red);
                    Im3d.DrawAlignedBox (block_aabb.min, block_aabb.max);
                    Im3d.PopColor ();

                    if result.distance < closest_hit.distance
                    {
                        closest_hit = result;
                        closest_hit.chunk = null;
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
    }

    return closest_hit;
}
