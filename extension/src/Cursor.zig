const godot = @import("godot_zig");
const Node = godot.generated.classes.Node;
const Vector3 = godot.Vector3;
const Object = godot.generated.classes.Object;
const InputEvent = godot.generated.classes.InputEvent;
const InputEventMouseButton = godot.generated.classes.InputEventMouseButton;
const InptEventMouseMotion = godot.generated.classes.InputEventMouseMotion;

const util = @import("util/root.zig");
const stringNameEqual = util.stringNameEqual;

const Self = @This();

object: godot.c.GDExtensionObjectPtr,
mouse_movement_class: godot.StringName,
mouse_button_class: godot.StringName,

pub const ContactSignal = struct {
    pub const signal_name: [:0]const u8 = "contact_requested";

    point: Vector3 = .{ .x = 0, .y = 0, .z = 0 },
};

pub fn init(object: godot.c.GDExtensionObjectPtr) Self {
    return .{
        .object = object,
        .mouse_movement_class = godot.api.godot.stringName("InputEventMouseMotion"),
        .mouse_button_class = godot.api.godot.stringName("InputEventMouseButton"),
    };
}

pub fn deinit(self: *Self) void {
    godot.api.godot.destroy(
        godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME,
        &self.mouse_movement_class,
    );
    godot.api.godot.destroy(
        godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME,
        &self.mouse_button_class,
    );
}

pub fn ready(self: *Self) callconv(.c) void {
    const node = Node.init(self.object);
    node.set_process_input(true);
}

pub fn handleInput(self: *Self, raw_event: godot.c.GDExtensionObjectPtr) callconv(.c) void {
    const object = Object.init(raw_event);
    if (!object.is_class(self.mouse_button_class)) return;

    const mouse = InputEventMouseButton.init(raw_event);
    if (mouse.get_button_index() != 1) return;

    const event = InputEvent.init(raw_event);
    if (event.is_pressed()) {
        const sender = godot.Object.init(self.object);
        _ = sender.emitSignal(ContactSignal, .{}) catch return;
    }
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
