const godot = @import("godot_zig");
const Node = godot.generated.classes.Node;

const util = @import("util/root.zig");
const stringNameEqual = util.stringNameEqual;

const Self = @This();

object: godot.c.GDExtensionObjectPtr,
mouse_movement_class: godot.StringName,

pub fn ready(self: *Self) callconv(.c) void {
    const node = Node.init(self.object);
    node.set_process_input(true);
}

pub fn handleInput(self: *Self, raw_event: godot.c.GDExtensionObjectPtr) callconv(.c) void {
    const Object = godot.generated.classes.Object;
    const InputEvent = godot.generated.classes.InputEvent;
    const InputEventMouseButton = godot.generated.classes.InputEventMouseButton;
    const InptEventMouseMotion = godot.generated.classes.InputEventMouseMotion;
}

pub fn getVirtualCallData(_: ?*anyopaque, name: godot.c.GDExtensionConstStringNamePtr, _: u32) callconv(.c) ?*anyopaque {
    var ready_name = godot.api.godot.stringName("_ready");
    defer godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME, &ready_name);
    var handle_input_name = godot.api.godot.stringName("_input");
    defer godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME, &handle_input_name);

    if (stringNameEqual(name, &ready_name)) return @ptrCast(@constCast(&ready));
    if (stringNameEqual(name, &handle_input_name)) return @ptrCast(@constCast(&handleInput));

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

    if (userdata == @as(?*anyopaque, @ptrCast(@constCast(&handleInput)))) {
        const event_ptr: *const godot.c.GDExtensionObjectPtr = @ptrCast(@alignCast(args[0].?));
        handleInput(self, event_ptr.*);
        return;
    }
}
