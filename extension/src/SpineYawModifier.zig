const godot = @import("godot_zig");

const SkeletonModifier3D = godot.generated.classes.SkeletonModifier3D;
const Quaternion = godot.Quaternion;
const stringNameEqual = @import("util/root.zig").stringNameEqual;
const Self = @This();

object: godot.c.GDExtensionObjectPtr,
yaw: f64 = 0.0,
spine_bone: i64 = -1,

pub fn init(object: godot.c.GDExtensionObjectPtr) Self {
    return .{ .object = object };
}

pub fn deinit(_: *Self) void {}

pub fn getYaw(self: *Self) callconv(.c) f64 {
    return self.yaw;
}

pub fn setYaw(self: *Self, yaw: f64) callconv(.c) void {
    self.yaw = yaw;
}

fn processModificationWithDelta(self: *Self, _: f64) callconv(.c) void {
    processModification(self);
}

fn processModification(self: *Self) callconv(.c) void {
    const modifier = SkeletonModifier3D.init(self.object);
    const skeleton = modifier.get_skeleton();
    if (skeleton.isNull()) return;

    if (self.spine_bone < 0) {
        var bone_name = godot.api.godot.string("spine_01");
        defer godot.api.godot.destroy(
            godot.c.GDEXTENSION_VARIANT_TYPE_STRING,
            &bone_name,
        );
        self.spine_bone = skeleton.find_bone(bone_name);
        if (self.spine_bone < 0) return;
    }

    // A modifier receives the pose produced by AnimationTree, so the twist
    // starts from the animated pose rather than accumulating each frame.
    const animated_rotation = skeleton.get_bone_pose_rotation(self.spine_bone);
    const half_angle: f32 = @floatCast(self.yaw * 0.5);
    const twist = Quaternion{
        .x = 0.0,
        .y = @sin(half_angle),
        .z = 0.0,
        .w = @cos(half_angle),
    };

    skeleton.set_bone_pose_rotation(
        self.spine_bone,
        animated_rotation.multiply(twist),
    );
}

pub fn getVirtualCallData(
    _: ?*anyopaque,
    name: godot.c.GDExtensionConstStringNamePtr,
    _: u32,
) callconv(.c) ?*anyopaque {
    var process_name = godot.api.godot.stringName("_process_modification");
    defer godot.api.godot.destroy(
        godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME,
        &process_name,
    );
    var process_delta_name = godot.api.godot.stringName("_process_modification_with_delta");
    defer godot.api.godot.destroy(
        godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME,
        &process_delta_name,
    );

    if (stringNameEqual(name, &process_name))
        return @ptrCast(@constCast(&processModification));
    if (stringNameEqual(name, &process_delta_name))
        return @ptrCast(@constCast(&processModificationWithDelta));

    return null;
}

pub fn callVirtualWithData(
    instance: godot.c.GDExtensionClassInstancePtr,
    _: godot.c.GDExtensionConstStringNamePtr,
    userdata: ?*anyopaque,
    args: [*c]const godot.c.GDExtensionConstTypePtr,
    _: godot.c.GDExtensionTypePtr,
) callconv(.c) void {
    const self: *Self = @ptrCast(@alignCast(instance.?));

    if (userdata == @as(?*anyopaque, @ptrCast(@constCast(&processModification)))) {
        processModification(self);
        return;
    }
    if (userdata == @as(?*anyopaque, @ptrCast(@constCast(&processModificationWithDelta)))) {
        const delta: *const f64 = @ptrCast(@alignCast(args[0].?));
        processModificationWithDelta(self, delta.*);
    }
}
