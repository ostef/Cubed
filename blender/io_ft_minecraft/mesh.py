import bpy
import bmesh
import mathutils

from typing import (
    List,
    Dict,
    Tuple
)

from bpy.props import (
    StringProperty,
    BoolProperty,
    FloatProperty
)

from bpy_extras.io_utils import (
    ExportHelper,
    orientation_helper,
    axis_conversion
)

class Vertex:
    def __init__ (
        self,
        position : Tuple[float, float, float],
        normal   : Tuple[float, float, float],
        tex_coords : Tuple[float, float],
        joint_id : int,
    ):
        self.position = position
        self.normal = normal
        self.tex_coords = tex_coords
        self.joint_id = joint_id

class Mesh:
    def __init__ (
        self
    ):
        self.name_to_joint_id : Dict[str, int] = {}
        self.joints : List[bpy.types.Bone] = []
        self.verts : List[Vertex] = []
        self.tris : List[Tuple[int, int, int]] = []

    def FromMeshAndArmature (
        blender_obj : bpy.types.Object,
        blender_mesh : bpy.types.Mesh,
        blender_armature : bpy.types.Armature
    ):
        def AppendHierarchy (joints : List[bpy.types.Bone], bone : bpy.types.Bone):
            joints.append (bone)

            for child in bone.children:
                if child.use_deform:
                    AppendHierarchy (joints, child)

        result = Mesh ()

        if blender_armature is not None:
            # Fill skeleton data
            root = None

            # Find the root bone
            for b in blender_armature.bones:
                if b.parent is None and b.use_deform:
                    if root is not None:
                        raise Exception ("Found multiple root bones in armature.")
                    root = b

            if root is None:
                raise Exception ("Could not find root bone.")

            AppendHierarchy (result.joints, root)

            if len (result.joints) > 0x7fff:
                raise Exception (f"Armature has { len (result.joints) } bones, which is more than the maximum allowed ({0x7fff}).")

            for i, b in enumerate (result.joints):
                result.name_to_joint_id.update ({ b.name : i })

        # Fill vertex and triangle data
        vert_group_names = { g.index : g.name for g in blender_obj.vertex_groups }
        vertices_dict = {}
        for i, poly in enumerate (blender_mesh.polygons):
            if len (poly.vertices) != 3:
                raise Exception ("Mesh has polygons that are not triangles. Make sure to triangulate the mesh prior.")

            for vert_idx, loop_idx in zip (poly.vertices, poly.loop_indices):
                uv_coords = blender_mesh.uv_layers.active.data[loop_idx].uv

            tri = []
            for vert_index, loop_index in zip (poly.vertices, poly.loop_indices):
                vert_id = (vert_index, loop_index)
                if vert_id in vertices_dict:
                    result_vert_index = vertices_dict[vert_id]
                else:
                    result_vert_index = len (result.verts)
                    vertices_dict.update ({ vert_id : result_vert_index })
                    vert = blender_mesh.vertices[vert_index]
                    uv_coords = blender_mesh.uv_layers.active.data[loop_index].uv

                    if len (vert.groups) != 0 and blender_armature is None:
                        raise Exception ("Mesh has vertices assigned to vertex groups, but we could not find an armature associated with it. Make sure it is parented to an armature, or it has a valid skin modifier.")

                    if len (vert.groups) > 1:
                        raise Exception (f"Vertex {vert_index} has more than 1 group assigned to it.")

                    joint_id = -1
                    if len (vert.groups) > 0:
                        group = vert.groups[0].group
                        name = vert_group_names[group]
                        if name not in result.name_to_joint_id:
                            raise Exception (f"Vertex is assigned to group {name} but we could not find a deform bone with this name in the armature.")
                        joint_id = result.name_to_joint_id[name]

                    result.verts.append (Vertex (
                        tuple (vert.co),
                        tuple (vert.normal),
                        uv_coords,
                        joint_id
                    ))

                tri.append (result_vert_index)

            result.tris.append ((tri[0], tri[1], tri[2]))

        return result

    def WriteBinary (self, filename : str):
        import struct

        with open (filename, "wb") as file:
            fw = file.write

            fw (b"SKINNED_MESH")
            fw (struct.pack ("<I", 10000)) # File version

            fw (struct.pack ("<I", len (self.verts)))
            fw (struct.pack ("<I", len (self.tris)))

            for vert in self.verts:
                fw (struct.pack ("<fff", *vert.position))
                fw (struct.pack ("<fff", *vert.normal))
                fw (struct.pack ("<ff", *vert.tex_coords))
                fw (struct.pack ("<h", vert.joint_id))
                fw (struct.pack ("xx"))

            for tri in self.tris:
                fw (struct.pack ("<III", *tri))

            fw (struct.pack ("<h", len (self.joints)))
            for joint in self.joints:
                fw (b"%s\0" % bytes (joint.name, 'UTF-8'))

                if joint.parent is not None:
                    local_transform = joint.parent.matrix_local.inverted () @ joint.matrix_local
                else:
                    local_transform = joint.matrix_local

                fw (struct.pack ("<ffff", *local_transform[0]))
                fw (struct.pack ("<ffff", *local_transform[1]))
                fw (struct.pack ("<ffff", *local_transform[2]))
                fw (struct.pack ("<ffff", *local_transform[3]))

                if joint.parent is not None:
                    fw (struct.pack ("<h", self.name_to_joint_id[joint.parent.name]))
                else:
                    fw (struct.pack ("<h", -1))

def ExportMeshes (
    context : bpy.types.Context,
    filename : str,
    use_selection : bool,
    apply_transform : bool,
    axis_conversion_matrix : mathutils.Matrix
):
    import os

    if bpy.ops.object.mode_set.poll ():
        bpy.ops.object.mode_set (mode = 'OBJECT')

    if use_selection:
        objs = context.selected_objects
    else:
        objs = context.scene.objects

    for obj in objs:
        try:
            me = obj.to_mesh ()
        except RuntimeError:
            continue

        armature_obj = obj.find_armature ()
        armature = bpy.types.Armature = None
        if armature_obj is not None:
            armature = armature_obj.data.copy ()

        # Apply object transform and calculate normals
        if apply_transform:
            me.transform (obj.matrix_world)
            if armature is not None:
                armature.transform (obj.matrix_world)

        if axis_conversion_matrix is not None:
            me.transform (axis_conversion_matrix.to_4x4 ())
            if armature is not None:
                armature.transform (axis_conversion_matrix.to_4x4 ())

        me.calc_normals ()

        # Triangulate mesh
        bm = bmesh.new ()
        bm.from_mesh (me)
        bmesh.ops.triangulate (bm, faces = bm.faces[:])
        bm.to_mesh (me)
        bm.free ()

        result = Mesh.FromMeshAndArmature (obj, me, armature)
        output_filename = os.path.join (os.path.dirname (filename), obj.name) + Exporter.filename_ext
        result.WriteBinary (output_filename)
        obj.to_mesh_clear ()

        print (f"Exported mesh {obj.name} to file {output_filename}")

@orientation_helper (axis_forward = '-Z', axis_up = 'Y')
class Exporter (bpy.types.Operator, ExportHelper):
    """Export mesh data"""
    bl_idname = "export.anim_example_mesh"
    bl_label = "Export mesh with skinning (.mesh)"
    bl_options = { 'REGISTER', 'UNDO' }
    filename_ext = ".mesh"

    use_selection : BoolProperty (
        name = "Only Selected",
        description = "Export only the selected meshes.",
        default = True
    )

    apply_transform : BoolProperty (
        name = "Apply object transform",
        description = "Apply the object transform matrix when exporting meshes.",
        default = True
    )

    def execute (self, context : bpy.types.Context):
        context.window.cursor_set ('WAIT')
        ExportMeshes (
            context,
            self.filepath,
            self.use_selection,
            self.apply_transform,
            axis_conversion (to_forward = self.axis_forward, to_up = self.axis_up)
        )
        context.window.cursor_set ('DEFAULT')

        return { 'FINISHED' }

def export_menu_func (self, context : bpy.types.Context):
    self.layout.operator (Exporter.bl_idname)
