const std = @import("std");
const godot = @import("godot_zig");

const SoftBody3D = godot.generated.classes.SoftBody3D;
const MeshInstance3D = godot.generated.classes.MeshInstance3D;
const Engine = godot.generated.classes.Engine;
const Vector3 = godot.Vector3;

const Particle = struct {};

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

fn logReady(message: [*:0]const u8) void {
    godot.log.errMsg("avocado", message, .{
        .function = @src().fn_name,
        .file = @src().file,
        .line = @src().line,
        .editor_notify = false,
    });
}

const Avocado = struct {
    object: godot.c.GDExtensionObjectPtr,
    impulse_timer: f64,
    alloc: std.mem.Allocator = std.heap.c_allocator,

    rest_vertices: []Vector3 = &.{},
    cur_vertices: []Vector3 = &.{},
    indices: []i32 = &.{},
    particles: []Particle = &.{},

    pub fn init(object: godot.c.GDExtensionObjectPtr) Avocado {
        return .{ .object = object, .impulse_timer = 0.0 };
    }

    fn asNode(self: *Avocado) godot.Node {
        return godot.Node.init(self.object);
    }

    fn asSoftBody(self: *Avocado) SoftBody3D {
        return SoftBody3D.init(self.object);
    }

    fn asMeshInstance(self: *Avocado) MeshInstance3D {
        return MeshInstance3D.init(self.object);
    }

    fn ready(self: *Avocado) callconv(.c) void {
        // The editor may instantiate scene nodes while loading/inspecting scenes.
        // Do not crawl mesh data there; native crashes kill the whole editor.
        if (Engine.singleton().is_editor_hint()) return;

        logReady("READY RAN");

        const mesh_instance = self.asMeshInstance();
        const mesh = mesh_instance.get_mesh();

        if (mesh.isNull()) {
            logReady("mesh is null; skipping vertex cache");
            return;
        }

        var seen = std.AutoHashMap(QuantizedVertexKey, void).init(self.alloc);
        defer seen.deinit();

        const surface_count = mesh.get_surface_count();

        var buf: std.ArrayList(Vector3) = .empty;
        errdefer buf.deinit(self.alloc);

        var surface_i: i64 = 0;
        while (surface_i < surface_count) : (surface_i += 1) {
            var arrays = mesh.surface_get_arrays(surface_i);
            defer arrays.destroy();

            var vertices = arrays.vertices();
            defer vertices.destroy();

            const vertex_count = vertices.size();

            var i: i64 = 0;
            while (i < vertex_count) : (i += 1) {
                const p = vertices.get(i);
                const qp: QuantizedVertexKey = .fromVector3(p, 0.001);
                if (!seen.contains(qp)) {
                    seen.put(qp, {}) catch {
                        logReady("failed to insert vertex into seen map");
                        return;
                    };
                    buf.append(self.alloc, p) catch {
                        logReady("failed to append rest vertex");
                        return;
                    };
                }
            }
        }

        self.rest_vertices = buf.toOwnedSlice(self.alloc) catch {
            logReady("failed to own rest vertex slice");
            return;
        };

        var count_msg_buf: [64]u8 = undefined;
        const msg = std.fmt.bufPrintZ(&count_msg_buf, "there are {d} rest_vertices", .{self.rest_vertices.len}) catch {
            logReady("failed to format rest vertex count");
            return;
        };
        godot.log.errMsg("avocado", msg, .{
            .function = @src().fn_name,
            .file = @src().file,
            .line = @src().line,
            .editor_notify = false,
        });
    }

    fn physicsProcess(self: *Avocado, delta: f64) callconv(.c) void {
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
        const self: *Avocado = @ptrCast(@alignCast(instance.?));

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

    godot.class.NativeClass(Avocado, "MeshInstance3D", "Avocado").register();
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
