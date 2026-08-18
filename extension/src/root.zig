const std = @import("std");
const godot = @import("godot_zig");

const MeshInstance3D = godot.generated.classes.MeshInstance3D;
const Node = godot.generated.classes.Node;
const Vector3 = godot.Vector3;
const Mesh = godot.Mesh;

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
        }
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
        self.applySquash(0.45);
        self.recalculateNormals() catch {
            const msg = "Error calculating normals";
            log(msg);
            @panic(msg);
        };
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

            for (rest_vertices, 0..) |*vertex, i| {
                vertex.* = packed_vertices.get(@intCast(i));
            }

            @memcpy(vertices, rest_vertices);

            @memset(normals, .{});

            for (indices, 0..) |*index, i| {
                index.* = packed_indices.get(@intCast(i));
            }

            try self.surfaces.append(self.alloc, .{
                .arrays = arrays,
                .rest_vertices = rest_vertices,
                .vertices = vertices,
                .normals = normals,
                .indices = indices,
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

                // Leave this unnormalized for area-weighted normals.
                const face_normal = util.v3cross(ab, ac);

                util.v3addTo(&surface.normals[a], face_normal);
                util.v3addTo(&surface.normals[b], face_normal);
                util.v3addTo(&surface.normals[c], face_normal);
            }

            for (surface.normals) |*normal| {
                normal.* = normal.normalized();
            }
        }
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
