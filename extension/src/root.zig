const std = @import("std");
const godot = @import("godot_zig");

const SoftBody3D = godot.generated.classes.SoftBody3D;
const MeshInstance3D = godot.generated.classes.MeshInstance3D;
const ArrayMesh = godot.generated.classes.ArrayMesh;
const Crypto = godot.generated.classes.Crypto;
const Engine = godot.generated.classes.Engine;
const Mesh = godot.generated.classes.Mesh;
const PackedByteArray = godot.PackedByteArray;
const Vector3 = godot.Vector3;

const soft_mesh = @import("util/soft_mesh.zig");
const SoftBodySimulationParams = soft_mesh.Params;
const mesh_array_flag_use_dynamic_update: i64 = 67_108_864;

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

fn log(message: [*:0]const u8) void {
    godot.log.errMsg("avocado", message, .{
        .function = @src().fn_name,
        .file = @src().file,
        .line = @src().line,
        .editor_notify = false,
    });
}

const Jello = struct {
    object: godot.c.GDExtensionObjectPtr,
    alloc: std.mem.Allocator = std.heap.c_allocator,

    pub fn init(object: godot.c.GDExtensionObjectPtr) Jello {
        return .{ .object = object };
    }

    pub fn deinit(self: *Jello) void {
        _ = self;
        log("deinit called");
    }

    fn ready(self: *Jello) callconv(.c) void {
        _ = self;
    }

    fn physicsProcess(self: *Jello, delta: f64) callconv(.c) void {
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
        const self: *Jello = @ptrCast(@alignCast(instance.?));

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

    godot.class.NativeClass(Jello, "MeshInstance3D", "Avocado").register();
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
