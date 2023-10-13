const float Pi = 3.1415927;
const float To_Rads = Pi / 180.0;
const float To_Degs = 180.0 / Pi;

vec3 BilinearMix (vec3 a, vec3 b, vec3 c, vec3 d, float s, float t)
{
    vec3 x = mix (a, b, s);
    vec3 y = mix (c, d, s);

    return mix (x, y, t);
}

vec3 CartesianToSpherical (vec3 point)
{
    float radius = length (point);
    float azimuth = sign (point.z) * acos (point.x / length (point.xz));
    float polar = acos (point.y / radius);

    return vec3 (radius, azimuth, polar);
}

vec2 CartesianToSphericalUV (vec3 point)
{
    vec2 angles = CartesianToSpherical (point).yz;
    angles /= Pi;
    angles.x = 1 - (angles.x + 1) * 0.5;

    return angles;
}

vec3 SphericalToCartesian (vec3 point)
{
    float radius = point.x;
    float azimuth = point.y;
    float polar = point.z;
    float cosp = cos (polar);
    float sinp = sin (polar);
    float sina = sin (azimuth);
    float cosa = cos (azimuth);

    return radius * vec3 (sinp * cosa, cosp, sinp * sina);
}
