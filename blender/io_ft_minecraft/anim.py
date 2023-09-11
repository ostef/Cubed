import bpy
import mathutils

from typing import (
    List,
    Dict,
    Tuple
)

from bpy.props import (
    IntProperty,
    BoolProperty,
    EnumProperty
)

from bpy_extras.io_utils import (
    ExportHelper,
    orientation_helper,
    axis_conversion
)

Vec3f = Tuple[float, float, float]
Quatf = Tuple[float, float, float, float]

class JointSample:
    def __init__ (
        self,
        local_position : Vec3f,
        local_orientation : Quatf,
        local_scale : Vec3f
    ):
        self.local_position = local_position
        self.local_orientation = local_orientation
        self.local_scale = local_scale

class SkeletonPose:
    def __init__ (
        self,
        joint_count : int
    ):
        self.joints : List[JointSample] = [
            JointSample ((0,0,0), (0,0,0,1), (1,1,1))
            for i in range (joint_count)
        ]

class SampledAnimation:
    def __init__ (
        self
    ):
        self.name_to_joint_id : Dict[str, int] = {}
        self.poses : List[SkeletonPose] = []

    def FromAction (
        blender_obj : bpy.types.Object,
        blender_action : bpy.types.Action,
        frame_begin : int,
        frame_end : int,
        frame_step : int,
        transform_matrix : mathutils.Matrix
    ):
        def AppendPose (
            anim : SampledAnimation,
            blender_pose : bpy.types.Pose
        ):
            pose = SkeletonPose (len (anim.name_to_joint_id))
            for bone in blender_pose.bones:
                if bone.name not in anim.name_to_joint_id:
                    continue

                matrix : mathutils.Matrix = transform_matrix @ bone.matrix

                if bone.parent is not None:
                    parent_matrix = transform_matrix @ bone.parent.matrix
                    matrix = parent_matrix.inverted () @ matrix

                location, orientation, scale = matrix.decompose ()
                joint_index = anim.name_to_joint_id[bone.name]
                pose.joints[joint_index] = JointSample (location, orientation, scale)

            anim.poses.append (pose)

        result = SampledAnimation ()
        prev_action = blender_obj.animation_data.action
        prev_frame = bpy.context.scene.frame_current

        blender_obj.animation_data.action = blender_action
        bpy.context.scene.frame_set (frame_begin)

        # Initialize the name to joint id dict
        joint_count = 0
        for bone in blender_obj.pose.bones:
            if not bone.bone.use_deform:
                continue

            result.name_to_joint_id.update ({ bone.name : joint_count })
            joint_count += 1

        for frame in range (frame_begin, frame_end, frame_step):
            bpy.context.scene.frame_set (frame)
            AppendPose (result, blender_obj.pose)

        bpy.context.scene.frame_set (prev_frame)
        blender_obj.animation_data.action = prev_action

        return result

    def WriteBinary (self, filename : str):
        import struct

        with open (filename, "wb") as file:
            fw = file.write

            fw (b"ANIMATION")

            fw (struct.pack ("<I", 10000))

            fw (struct.pack ("<I", len (self.poses)))
            fw (struct.pack ("<I", len (self.name_to_joint_id)))
            for name in self.name_to_joint_id:
                fw (b"%s\0" % bytes (name, 'UTF-8'))

            for pose in self.poses:
                for joint in pose.joints:
                    fw (struct.pack ("<fff", *joint.local_position))
                    fw (struct.pack ("<ffff", *joint.local_orientation))
                    fw (struct.pack ("<fff", *joint.local_scale))

def ExportAnimations (
    context : bpy.types.Context,
    filename : str,
    use_action_frame_range : bool,
    frame_step : int,
    selected_objects_only : bool,
    active_action_only : bool,
    apply_transform : bool,
    axis_conversion_matrix : mathutils.Matrix
):
    import os

    if bpy.ops.object.mode_set.poll ():
        bpy.ops.object.mode_set (mode = 'OBJECT')

    if selected_objects_only:
        objs = context.selected_objects
    else:
        objs = context.scene.objects

    exported_actions : List[bpy.types.Action] = []
    for obj in objs:
        if obj.animation_data is None or obj.pose is None:
            continue

        action = obj.animation_data.action
        if action is None or action in exported_actions:
            continue

        transform_matrix = mathutils.Matrix.Identity (4)
        if apply_transform:
            transform_matrix = transform_matrix @ obj.matrix_world
        if axis_conversion_matrix is not None:
            transform_matrix = transform_matrix @ axis_conversion_matrix.to_4x4 ()

        output_filename = os.path.join (os.path.dirname (filename), action.name) + Exporter.filename_ext
        if use_action_frame_range:
            frame_begin, frame_end = (
                int (action.frame_range[0]),
                int (action.frame_range[1])
            )
        else:
            frame_begin, frame_end = (
                int (context.scene.frame_start),
                int (context.scene.frame_end)
            )

        anim = SampledAnimation.FromAction (obj, action, frame_begin, frame_end, frame_step, transform_matrix)
        anim.WriteBinary (output_filename)

        exported_actions.append (action)
        print (f"Exported animation clip {action.name} to file {output_filename}")

@orientation_helper (axis_forward = '-Z', axis_up = 'Y')
class Exporter (bpy.types.Operator, ExportHelper):
    """Export animation data"""
    bl_idname = "export.anim_example_anim"
    bl_label = "Export sampled animation (.anim)"
    bl_options = { 'REGISTER', 'UNDO' }
    filename_ext = ".anim"

    use_selection : BoolProperty (
        name = "Only Selected",
        description = "Export only the active action of the selected objects.",
        default = True
    )

    apply_transform : BoolProperty (
        name = "Apply object transform",
        description = "Apply the object transform matrix when exporting animations.",
        default = True
    )

    use_action_frame_range : BoolProperty (
        name = "Use action frame range",
        description = "Use the action frame range rather than the scene frame range.",
        default = False
    )

    frame_step : IntProperty (
        name = "Frame step",
        description = "How many frames to advance when sampling the animation.",
        default = 1
    )

    def execute (self, context : bpy.types.Context):
        context.window.cursor_set ('WAIT')
        ExportAnimations (
            context,
            self.filepath,
            self.use_action_frame_range,
            self.frame_step,
            self.use_selection,
            self.apply_transform,
            axis_conversion (to_forward = self.axis_forward, to_up = self.axis_up)
        )
        context.window.cursor_set ('DEFAULT')

        return { 'FINISHED' }

def export_menu_func (self, context : bpy.types.Context):
    self.layout.operator (Exporter.bl_idname)
