const std = @import("std");
const godot = @import("godot_zig");
const Node = godot.generated.classes.Node;
const MeshInstance3D = godot.generated.classes.MeshInstance3D;
const Node3D = godot.generated.classes.Node3D;
const Mesh = godot.Mesh;
const Vector3 = godot.Vector3;

const util = @import("util/root.zig");
const SimulatedSurface = util.SimulatedSurface;
const stringNameEqual = util.stringNameEqual;
const log = @import("util/root.zig").log;

const Self = @This();

object: godot.c.GDExtensionObjectPtr,
simulated_surface: SimulatedSurface = .{},
mouse_button_class: godot.StringName,

pub fn init(object: godot.c.GDExtensionObjectPtr) Self {
    return .{
        .object = object,
        .mouse_button_class = godot.api.godot.stringName("InputEventMouseButton"),
    };
}

pub fn deinit(self: *Self) void {
    self.simulated_surface.deinit();
    godot.api.godot.destroy(
        godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME,
        &self.mouse_button_class,
    );
    log("deinit called");
}

fn ready(self: *Self) callconv(.c) void {
    const node = Node.init(self.object);
    node.set_physics_process(true);

    const visual = MeshInstance3D.init(self.object);

    self.simulated_surface.prime(&visual) catch {
        const message = "Error preparing simulated surface";
        log(message);
        @panic(message);
    };
}

pub fn onContactRequested(self: *Self, point_world: Vector3) callconv(.c) void {
    const point_local = Node3D.init(self.object).to_local(point_world);
    const rest_center = self.simulated_surface.rest_center;
    const squash_axis = util.v3subtract(point_local, rest_center).normalized();

    self.simulated_surface.excite(.{
        .point_local = point_local,
        .normal_local = squash_axis,
        .strength = 4.0,
    });
}

fn physicsProcess(self: *Self, delta: f64) callconv(.c) void {
    self.simulated_surface.tick(delta) catch {
        log("Error updating simulated surface");
    };
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
    const self: *Self = @ptrCast(@alignCast(instance.?));

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
