#scope_module

Linalg :: #import "Linalg";

Vec2 :: Linalg.Vec2f;
Vec3 :: Linalg.Vec3f;
Vec4 :: Linalg.Vec4f;
Mat3 :: Linalg.Mat3f;
Mat4 :: Linalg.Mat4f;

#scope_export

#if OS == .WINDOWS
    #load "windows.jai";
else #if OS == .LINUX
    #load "linux.jai";
else
    #assert false "Unsupported OS";
