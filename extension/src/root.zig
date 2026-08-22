const std = @import("std");
const godot = @import("godot_zig");

const MeshInstance3D = godot.generated.classes.MeshInstance3D;
const Node = godot.generated.classes.Node;
const Vector3 = godot.Vector3;
const Mesh = godot.Mesh;
const ArrayMesh = godot.generated.classes.ArrayMesh;

const util = @import("util/root.zig");
const log = util.log;
const logStringName = util.logStringName;
const soft_mesh = @import("util/soft_mesh.zig");
const SoftBodySimulationParams = soft_mesh.Params;
const mesh_array_flag_use_dynamic_update: i64 = 67_108_864;

const SurfaceCache = struct {
    rest_vertices: []Vector3,
    vertices: []Vector3,
    normals: []Vector3,
    indices: []i32,
    normal_groups: []usize,
    normal_sums: []Vector3,
    vertex_upload: godot.PackedByteArray,

    primitive_type: i64 = 3,
    arrays: godot.Array,
};

const QuantizedVertexKey = struct {
    x: i64,
    y: i64,
    z: i64,

    fn fromVector3(v: godot.types.Vector3, epsilon: f32) QuantizedVertexKey {
        return .{
            .x = @intFromFloat(@round(v.x / epsilon)),
            .y = @intFromFloat(@round(v.y / epsilon)),
            .z = @intFromFloat(@round(v.z / epsilon)),
        };
    }
};

const JelloVisual = struct {
    object: godot.c.GDExtensionObjectPtr,
    alloc: std.mem.Allocator = std.heap.c_allocator,

    surfaces: std.ArrayList(SurfaceCache) = .empty,
    rest_center: Vector3 = .{ .x = 0, .y = 0, .z = 0 },
    dynamic_mesh: ?ArrayMesh = null,

    pub fn init(object: godot.c.GDExtensionObjectPtr) JelloVisual {
        return .{ .object = object };
    }

    pub fn deinit(self: *JelloVisual) void {
        for (self.surfaces.items) |*surface| {
            surface.arrays.destroy();
            self.alloc.free(surface.rest_vertices);
            self.alloc.free(surface.vertices);
            self.alloc.free(surface.normals);
            self.alloc.free(surface.indices);
            self.alloc.free(surface.normal_groups);
            self.alloc.free(surface.normal_sums);
            surface.vertex_upload.destroy();
        }
        self.surfaces.deinit(self.alloc);
        log("deinit called");
    }

    fn ready(self: *JelloVisual) callconv(.c) void {
        const visual = MeshInstance3D.init(self.object);
        const source_mesh = visual.get_mesh();

        if (source_mesh.isNull()) {
            log("JelloVisual mesh not ready");
            return;
        }

        self.collectSurfaces(&source_mesh) catch {
            const msg = "Error collecting surfaces";
            log(msg);
            @panic(msg);
        };

        self.calculateRestCenter();
        self.applySquash(0.30);
        self.recalculateNormals() catch {
            const msg = "Error calculating normals";
            log(msg);
            @panic(msg);
        };
        self.createDynamicMesh();
        self.setMeshInitial();
        // for testing, delete later
        self.updateDeformedMesh();
    }

    fn collectSurfaces(self: *JelloVisual, source_mesh: *const Mesh) !void {
        const surface_count = source_mesh.get_surface_count();

        var surface_i: i64 = 0;
        while (surface_i < surface_count) : (surface_i += 1) {
            var arrays = source_mesh.surface_get_arrays(surface_i);
            errdefer arrays.destroy();

            var packed_vertices = arrays.vertices();
            defer packed_vertices.destroy();

            var packed_indices = arrays.indices();
            defer packed_indices.destroy();

            const vertex_count: usize = @intCast(packed_vertices.size());
            const index_count: usize = @intCast(packed_indices.size());

            if (index_count == 0)
                return error.MeshHasNoIndices;

            // copy
            const rest_vertices = try self.alloc.alloc(Vector3, vertex_count);
            errdefer self.alloc.free(rest_vertices);

            const vertices = try self.alloc.alloc(Vector3, vertex_count);
            errdefer self.alloc.free(vertices);

            const normals = try self.alloc.alloc(Vector3, vertex_count);
            errdefer self.alloc.free(normals);

            const indices = try self.alloc.alloc(i32, index_count);
            errdefer self.alloc.free(indices);

            const normal_groups = try self.alloc.alloc(usize, vertex_count);
            errdefer self.alloc.free(normal_groups);

            for (rest_vertices, 0..) |*vertex, i| {
                vertex.* = packed_vertices.get(@intCast(i));
            }

            @memcpy(vertices, rest_vertices);

            var vertex_upload = godot.PackedByteArray.fromSlice(
                std.mem.sliceAsBytes(vertices),
            );
            errdefer vertex_upload.destroy();

            @memset(normals, .{});

            for (indices, 0..) |*index, i| {
                index.* = packed_indices.get(@intCast(i));
            }

            // Build seam-welding groups once. Normal updates reuse these arrays.
            var group_by_position = std.AutoHashMap(QuantizedVertexKey, usize).init(self.alloc);
            defer group_by_position.deinit();

            var group_count: usize = 0;
            for (rest_vertices, 0..) |rest, i| {
                const key = QuantizedVertexKey.fromVector3(rest, 0.0001);
                const entry = try group_by_position.getOrPut(key);
                if (!entry.found_existing) {
                    entry.value_ptr.* = group_count;
                    group_count += 1;
                }
                normal_groups[i] = entry.value_ptr.*;
            }

            const normal_sums = try self.alloc.alloc(Vector3, group_count);
            errdefer self.alloc.free(normal_sums);
            @memset(normal_sums, .{});

            try self.surfaces.append(self.alloc, .{
                .arrays = arrays,
                .rest_vertices = rest_vertices,
                .vertices = vertices,
                .normals = normals,
                .indices = indices,
                .normal_groups = normal_groups,
                .normal_sums = normal_sums,
                .vertex_upload = vertex_upload,
            });
        }
    }

    fn calculateRestCenter(self: *JelloVisual) void {
        const first = self.surfaces.items[0].rest_vertices[0];

        var min = first;
        var max = first;

        for (self.surfaces.items) |*surface| {
            for (surface.rest_vertices) |*vertex| {
                min.x = @min(min.x, vertex.x);
                min.y = @min(min.y, vertex.y);
                min.z = @min(min.z, vertex.z);

                max.x = @max(max.x, vertex.x);
                max.y = @max(max.y, vertex.y);
                max.z = @max(max.z, vertex.z);
            }
        }

        self.rest_center = .{
            .x = (min.x + max.x) * 0.5,
            .y = (min.y + max.y) * 0.5,
            .z = (min.z + max.z) * 0.5,
        };
    }

    fn applySquash(self: *JelloVisual, squash: f32) void {
        const safe_squash = @min(@max(squash, 0.0), 0.65);
        const axial = 1.0 - safe_squash;
        const transverse = 1.0 / @sqrt(axial);

        for (self.surfaces.items) |surface| {
            for (
                surface.rest_vertices,
                surface.vertices,
            ) |rest, *out| {
                const offset = Vector3{
                    .x = rest.x - self.rest_center.x,
                    .y = rest.y - self.rest_center.y,
                    .z = rest.z - self.rest_center.z,
                };

                out.* = .{
                    .x = self.rest_center.x + offset.x * transverse,
                    .y = self.rest_center.y + offset.y * axial,
                    .z = self.rest_center.z + offset.z * transverse,
                };
            }
        }
    }

    fn recalculateNormals(self: *JelloVisual) !void {
        for (self.surfaces.items) |surface| {
            @memset(surface.normals, .{});

            var i: usize = 0;
            while (i + 2 < surface.indices.len) : (i += 3) {
                const raw_a = surface.indices[i];
                const raw_b = surface.indices[i + 1];
                const raw_c = surface.indices[i + 2];

                if (raw_a < 0 or raw_b < 0 or raw_c < 0)
                    return error.InvalidMeshIndex;

                const a: usize = @intCast(raw_a);
                const b: usize = @intCast(raw_b);
                const c: usize = @intCast(raw_c);

                if (a >= surface.vertices.len or
                    b >= surface.vertices.len or
                    c >= surface.vertices.len)
                {
                    return error.InvalidMeshIndex;
                }

                const ab = util.v3subtract(
                    surface.vertices[b],
                    surface.vertices[a],
                );

                const ac = util.v3subtract(
                    surface.vertices[c],
                    surface.vertices[a],
                );

                const face_normal = util.v3cross(ac, ab);

                util.v3addTo(&surface.normals[a], face_normal);
                util.v3addTo(&surface.normals[b], face_normal);
                util.v3addTo(&surface.normals[c], face_normal);
            }

            @memset(surface.normal_sums, .{});

            for (surface.normals, surface.normal_groups) |normal, group| {
                util.v3addTo(&surface.normal_sums[group], normal);
            }

            for (surface.normals, surface.normal_groups) |*normal, group| {
                normal.* = surface.normal_sums[group].normalized();
            }
        }
    }

    fn createDynamicMesh(self: *JelloVisual) void {
        const dynamic_mesh = util.createArrayMesh();

        var blend_shapes = util.createEmptyArray();
        defer blend_shapes.destroy();

        var lods = util.createEmtpyDictionary();
        defer godot.api.godot.destroy(
            godot.c.GDEXTENSION_VARIANT_TYPE_DICTIONARY,
            &lods,
        );

        for (self.surfaces.items) |surface| {
            dynamic_mesh.add_surface_from_arrays(
                surface.primitive_type,
                surface.arrays,
                blend_shapes,
                lods,
                mesh_array_flag_use_dynamic_update,
            );
        }

        self.dynamic_mesh = dynamic_mesh;
    }

    fn updateDeformedMesh(self: *JelloVisual) void {
        const dynamic_mesh = self.dynamic_mesh orelse {
            log("Dynamic mesh not created");
            return;
        };

        for (self.surfaces.items, 0..) |*surface, surface_i| {
            const bytes = std.mem.sliceAsBytes(surface.vertices);

            for (bytes, 0..) |byte, byte_i| {
                surface.vertex_upload.set(@intCast(byte_i), byte);
            }

            dynamic_mesh.surface_update_vertex_region(
                @intCast(surface_i),
                0,
                surface.vertex_upload,
            );
        }
    }

    fn setMeshInitial(self: *JelloVisual) void {
        const dynamic_mesh = self.dynamic_mesh orelse {
            log("Dynamic mesh not created");
            return;
        };

        const visual = MeshInstance3D.init(self.object);
        visual.set_mesh(Mesh.init(dynamic_mesh.asObject().ptr));
    }

    fn physicsProcess(self: *JelloVisual, delta: f64) callconv(.c) void {
        _ = self;
        _ = delta;
    }

    pub fn getVirtualCallData(_: ?*anyopaque, name: godot.c.GDExtensionConstStringNamePtr, _: u32) callconv(.c) ?*anyopaque {
        var ready_name = godot.api.godot.stringName("_ready");
        defer godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME, &ready_name);
        var physics_name = godot.api.godot.stringName("_physics_process");
        defer godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME, &physics_name);

        if (stringNameEqual(name, &ready_name)) return @ptrCast(@constCast(&ready));
        if (stringNameEqual(name, &physics_name)) return @ptrCast(@constCast(&physicsProcess));
        return null;
    }

    pub fn callVirtualWithData(
        instance: godot.c.GDExtensionClassInstancePtr,
        _: godot.c.GDExtensionConstStringNamePtr,
        userdata: ?*anyopaque,
        args: [*c]const godot.c.GDExtensionConstTypePtr,
        ret: godot.c.GDExtensionTypePtr,
    ) callconv(.c) void {
        _ = ret;
        const self: *JelloVisual = @ptrCast(@alignCast(instance.?));

        if (userdata == @as(?*anyopaque, @ptrCast(@constCast(&ready)))) {
            ready(self);
            return;
        }

        if (userdata == @as(?*anyopaque, @ptrCast(@constCast(&physicsProcess)))) {
            const delta: *const f64 = @ptrCast(@alignCast(args[0].?));
            physicsProcess(self, delta.*);
            return;
        }
    }
};

fn stringNameEqual(a: godot.c.GDExtensionConstStringNamePtr, b: godot.c.GDExtensionConstStringNamePtr) bool {
    const evaluator = godot.api.godot.variant_get_ptr_operator_evaluator.?(
        godot.c.GDEXTENSION_VARIANT_OP_EQUAL,
        godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME,
        godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME,
    ).?;
    var out: u8 = 0;
    evaluator(a, b, &out);
    return out != 0;
}

fn initialize(level: godot.c.GDExtensionInitializationLevel) callconv(.c) void {
    if (level != godot.c.GDEXTENSION_INITIALIZATION_SCENE) return;

    godot.class.NativeClass(JelloVisual, "MeshInstance3D", "JelloVisual").register();
}

fn deinitialize(level: godot.c.GDExtensionInitializationLevel) callconv(.c) void {
    _ = level;
}

pub export fn avocado_extension_init(
    get_proc_address: godot.c.GDExtensionInterfaceGetProcAddress,
    library: godot.c.GDExtensionClassLibraryPtr,
    initialization: [*c]godot.c.GDExtensionInitialization,
) godot.c.GDExtensionBool {
    return godot.extension.entry(
        get_proc_address,
        library,
        initialization,
        .scene,
        initialize,
        deinitialize,
    );
}
