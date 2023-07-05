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
    // @Todo: ensure correctness when ray.direction has zero components

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
        result.position = ray.origin + ray.direction * distance;
        result.hit = true;
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
