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

    pub fn init(object: godot.c.GDExtensionObjectPtr) JelloVisual {
        return .{ .object = object };
    }

    pub fn deinit(self: *JelloVisual) void {
        _ = self;
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

        var buf: [64]u8 = undefined;
        const buf_to_print = std.fmt.bufPrintZ(&buf, "Number of surfaces: {d}", .{self.surfaces.items.len}) catch @panic("");
        log(buf_to_print);
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
