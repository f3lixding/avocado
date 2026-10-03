const std = @import("std");
const godot = @import("godot_zig");
const classes = godot.generated.classes;

const Node = classes.Node;
const Node3D = classes.Node3D;
const MeshInstance3D = classes.MeshInstance3D;
const ArrayMesh = classes.ArrayMesh;
const Mesh = classes.Mesh;
const Vector3 = godot.Vector3;

const util = @import("util/root.zig");
const stringNameEqual = util.stringNameEqual;

const Self = @This();

pub const RuntimeNames = struct {
    // function names
    ready: godot.StringName,
    process: godot.StringName,

    pub fn init() RuntimeNames {
        return .{
            .ready = godot.api.godot.stringName("_ready"),
            .process = godot.api.godot.stringName("_process"),
        };
    }

    pub fn deinit(self: *RuntimeNames) void {
        godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME, &self.ready);
        godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME, &self.process);
    }
};

object: godot.c.GDExtensionObjectPtr,
names: *RuntimeNames,

blade_base: ?Node3D = null,
blade_tip: ?Node3D = null,
trail_visual: ?MeshInstance3D = null,
trail_mesh: ?ArrayMesh = null,

pub fn initWithUserdata(object: godot.c.GDExtensionObjectPtr, class_userdata: ?*anyopaque) Self {
    const names: *RuntimeNames = @ptrCast(@alignCast(class_userdata));
    return .{
        .object = object,
        .names = names,
    };
}

pub fn deinit(self: *Self) void {
    _ = self;
}

pub fn ready(self: *Self) callconv(.c) void {
    _ = self;
}

pub fn process(self: *Self, delta: f64) callconv(.c) void {
    _ = self;
    _ = delta;
}

pub fn getVirtualCallData(
    class_userdata: ?*anyopaque,
    name: godot.c.GDExtensionConstStringNamePtr,
    _: u32,
) callconv(.c) ?*anyopaque {
    const names: *RuntimeNames = @ptrCast(@alignCast(class_userdata.?));
    if (stringNameEqual(name, &names.ready)) return @ptrCast(@constCast(&ready));
    if (stringNameEqual(name, &names.process)) return @ptrCast(@constCast(&process));
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
    const self: *Self = @ptrCast(@alignCast(instance.?));

    if (userdata == @as(?*anyopaque, @ptrCast(@constCast(&ready)))) {
        ready(self);
    } else if (userdata == @as(?*anyopaque, @ptrCast(@constCast(&process)))) {
        const delta: *const f64 = @ptrCast(@alignCast(args[0].?));
        process(self, delta.*);
    }
}
