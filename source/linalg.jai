Linalg :: #import "Linalg";

ToRadians :: inline (angle_in_degrees : $T) -> T #must
{
	return angle_in_degrees * Pi / 180.0;
}

ToDegrees :: inline (angle_in_radians : $T) -> T #must
{
	return angle_in_degrees * 180.0 / Pi;
}

Vector :: Linalg.Vector;
Vec2f :: Linalg.Vec2f;
Vec2i :: Linalg.Vec2i;
Vec2l :: Linalg.Vec2l;
Vec3f :: Linalg.Vec3f;
Vec3l :: Linalg.Vec3l;
Vec4f :: Linalg.Vec4f;

Matrix :: Linalg.Matrix;
Mat3f :: Linalg.Mat3f;
Mat4f :: Linalg.Mat4f;
Mat3x4f :: Linalg.Mat3x4f;

Quaternion :: Linalg.Quat;
Quatf :: Linalg.Quatf;

Angle :: Linalg.angle;
Scale :: Linalg.scale;
Dot :: Linalg.dot;
SqrdLength :: Linalg.sqrd_length;
Length :: Linalg.length;
Normalized :: Linalg.normalized;
// Min :: Linalg.min;
// Max :: Linalg.max;
// Clamp :: Linalg.clamp;
// Round :: Linalg.round;
// Floor :: Linalg.floor;
// Ceil :: Linalg.ceil;
// Abs :: Linalg.abs;

Add :: Linalg.add;
Sub :: Linalg.sub;
Neg :: Linalg.neg;
Mul :: Linalg.mul;
Div :: Linalg.div;
Equals :: Linalg.equals;
ApproxZero :: Linalg.approx_zero;
ApproxEquals :: Linalg.approx_equals;

operator *[] :: Linalg.operator *[];
operator +   :: Linalg.operator +;
operator -   :: Linalg.operator -;
operator *   :: Linalg.operator *;
operator /   :: Linalg.operator /;
operator ==  :: Linalg.operator ==;

Lerp :: Linalg.lerp;
SqrdDistance :: Linalg.sqrd_distance;
Distance :: Linalg.distance;
Reflect :: Linalg.reflect;
Project :: Linalg.project;
Reject :: Linalg.reject;
Rotate :: Linalg.rotate;
SignedAngle :: Linalg.signed_angle;
PerpendicularCW :: Linalg.perpendicular_cw;
PerpendicularCCW :: Linalg.perpendicular_ccw;
Cross :: Linalg.cross;
RightToOrthonormalBasis :: Linalg.right_to_orthonormal_basis;
UpToOrthonormalBasis :: Linalg.up_to_orthonormal_basis;
ForwardToOrthonormalBasis :: Linalg.forward_to_orthonormal_basis;

TransformPoint :: Linalg.transform_point;
TransformVector :: Linalg.transform_vector;
GetRow :: Linalg.get_row;
SetRow :: Linalg.set_row;
GetCol :: Linalg.get_col;
SetCol :: Linalg.set_col;
Transposed :: Linalg.transposed;
ResizeMatrix :: Linalg.resize;

ToMat3f :: Linalg.to_mat3f;
MakeMat3f :: Linalg.mat3f;
Mat3fFromRightUpForward :: Linalg.mat3f_from_right_up_forward;
Mat3fFromQuat :: Linalg.mat3f_from_quat;
Mat3fFromAxisAngle :: Linalg.mat3f_from_axis_angle;
Mat3fRotate :: Linalg.mat3f_rotate;

RightVector :: Linalg.right_vector;
UpVector :: Linalg.up_vector;
ForwardVector :: Linalg.forward_vector;
ScaleVector :: Linalg.scale_vector;
RotationMatrix :: Linalg.rotation_matrix;
Inverse :: Linalg.inverse;

ToMat4f :: Linalg.to_mat4f;
MakeMat4f :: Linalg.mat4f;
Mat4fFromRightUpForwardOrigin :: Linalg.mat4f_from_right_up_forward_origin;
Mat4fFromQuat :: Linalg.mat4f_from_quat;
Mat4fFromAxisAngle :: Linalg.mat4f_from_axis_angle;
Mat4fRotate :: Linalg.mat4f_rotate;
Mat4fScale :: Linalg.mat4f_scale;
Mat4fTranslate :: Linalg.mat4f_translate;
Mat4fLookAt :: Linalg.mat4f_look_at;
Mat4fOrthographicProjection :: Linalg.mat4f_orthographic_projection;
Mat4fPerspectiveProjection :: Linalg.mat4f_perspective_projection;

TranslationVector :: Linalg.translation_vector;
Adjugate :: Linalg.adjugate;
Determinant :: Linalg.determinant;

QuatfLookAt :: Linalg.quatf_look_at;
QuatfFromAxisAngle :: Linalg.quatf_from_axis_angle;
QuatfFromEulerAngles :: Linalg.quatf_from_euler_angles;
QuatfFromMatrix :: Linalg.quatf_from_matrix;
ToAxisAngle :: Linalg.to_axis_angle;
Conjugate :: Linalg.conjugate;
NLerp :: Linalg.nlerp;

EulerAngles :: Linalg.Euler_Angles;
EulerAnglesFromQuat :: Linalg.euler_angles_from_quat;

SimpleDecomposeTransform :: (mat : Mat4f) -> translation : Vec3f, rotation : Quatf, scale : Vec3f
{
    return TranslationVector (mat), QuatfFromMatrix (mat), ScaleVector (mat);
}
