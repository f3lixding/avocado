const godot = @import("godot_zig");
const Node = godot.generated.classes.Node;
const Node3D = godot.generated.classes.Node3D;
const Vector3 = godot.Vector3;
const Vector2 = godot.Vector2;
const Camera3D = godot.generated.classes.Camera3D;
const RayCast3D = godot.generated.classes.RayCast3D;
const Object = godot.generated.classes.Object;
const InputEvent = godot.generated.classes.InputEvent;
const InputEventMouseButton = godot.generated.classes.InputEventMouseButton;
const InptEventMouseMotion = godot.generated.classes.InputEventMouseMotion;

const util = @import("util/root.zig");
const stringNameEqual = util.stringNameEqual;

const Self = @This();
const RAY_DISTANCE: f32 = 1000.0;

object: godot.c.GDExtensionObjectPtr,
mouse_movement_class: godot.StringName,
mouse_button_class: godot.StringName,
camera: ?Camera3D = null,
raycast: ?RayCast3D = null,
// We cache this because when only act when click is detected and that is not called in the same function / scope
current_hit: ?RayHit = null,

pub const ContactSignal = struct {
    pub const signal_name: [:0]const u8 = "contact_requested";

    point: Vector3 = .{ .x = 0, .y = 0, .z = 0 },
};

const RayHit = struct {
    point_world: Vector3,
    normal_world: Vector3,
    collider: Object,
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
    // node.set_process(true);

    const active_camera = node.get_viewport().get_camera_3d();
    self.camera = if (active_camera.isNull()) null else active_camera;
    self.raycast = blk: {
        var raycast_class = godot.api.godot.stringName("RayCast3D");
        defer godot.api.godot.destroy(
            godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME,
            &raycast_class,
        );

        const child_count = node.get_child_count(false);

        var idx: i64 = 0;
        while (idx < child_count) : (idx += 1) {
            const child = node.get_child(idx, false);

            const object = godot.generated.classes.Object.init(child.asObject().ptr);

            if (object.is_class(raycast_class)) {
                const raycast = RayCast3D.init(child.asObject().ptr);
                raycast.set_collision_mask(0);
                raycast.set_collision_mask_value(2, true);
                break :blk raycast;
            }
        } else @panic("Missing raycast");
    };
}

pub fn handleInput(self: *Self, raw_event: godot.c.GDExtensionObjectPtr) callconv(.c) void {
    const object = Object.init(raw_event);
    if (!object.is_class(self.mouse_button_class)) return;

    const mouse = InputEventMouseButton.init(raw_event);
    if (mouse.get_button_index() != 1) return;

    const event = InputEvent.init(raw_event);
    if (event.is_pressed()) {
        const hit = self.current_hit orelse return;
        const sender = godot.Object.init(self.object);
        _ = sender.emitSignal(ContactSignal, .{
            .point = hit.point_world,
        }) catch return;
    }
}

// TODO: maybe move this to input and only do this on mouse movement?
fn process(self: *Self, _: f64) callconv(.c) void {
    const camera = self.camera orelse return;
    if (camera.isNull()) return;
    const raycast = self.raycast orelse return;

    const mouse_position = Node.init(self.object).get_viewport().get_mouse_position();

    self.current_hit = castFromMouse(camera, raycast, mouse_position);

    const node_3d = Node3D.init(self.object);
    if (self.current_hit) |hit| {
        const surface_offset: f32 = 0.02;

        const cursor_position = Vector3{
            .x = hit.point_world.x + hit.normal_world.x * surface_offset,
            .y = hit.point_world.y + hit.normal_world.y * surface_offset,
            .z = hit.point_world.z + hit.normal_world.z * surface_offset,
        };

        const normal = hit.normal_world;

        const target_for_look_at = Vector3{
            .x = cursor_position.x + normal.x,
            .y = cursor_position.y + normal.y,
            .z = cursor_position.z + normal.z,
        };
        const up = if (@abs(normal.y) > 0.99)
            Vector3{ .x = 1.0, .y = 0.0, .z = 0.0 }
        else
            Vector3{ .x = 0.0, .y = 1.0, .z = 0.0 };

        node_3d.look_at(target_for_look_at, up, true);
        node_3d.set_global_position(cursor_position);
        node_3d.set_visible(true);

        godot.input_helpers.setMouseMode(godot.Input.singleton(), .hidden);
    } else {
        node_3d.set_visible(false);

        godot.input_helpers.setMouseMode(godot.Input.singleton(), .visible);
    }
}

fn castFromMouse(
    camera: Camera3D,
    raycast: RayCast3D,
    mouse_position: Vector2,
) ?RayHit {
    const origin = camera.project_ray_origin(mouse_position);
    const direction = camera.project_ray_normal(mouse_position);

    const endpoint = Vector3{
        .x = origin.x + direction.x * RAY_DISTANCE,
        .y = origin.y + direction.y * RAY_DISTANCE,
        .z = origin.z + direction.z * RAY_DISTANCE,
    };

    const ray_node = Node3D.init(raycast.asObject().ptr);
    ray_node.set_global_position(origin);

    raycast.set_target_position(ray_node.to_local(endpoint));

    raycast.force_raycast_update();

    if (!raycast.is_colliding()) {
        return null;
    }

    return .{
        .point_world = raycast.get_collision_point(),
        .normal_world = raycast.get_collision_normal(),
        .collider = raycast.get_collider(),
    };
}

pub fn getVirtualCallData(_: ?*anyopaque, name: godot.c.GDExtensionConstStringNamePtr, _: u32) callconv(.c) ?*anyopaque {
    var ready_name = godot.api.godot.stringName("_ready");
    defer godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME, &ready_name);
    var handle_input_name = godot.api.godot.stringName("_input");
    defer godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME, &handle_input_name);
    var process_name = godot.api.godot.stringName("_process");
    defer godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME, &process_name);

    if (stringNameEqual(name, &ready_name)) return @ptrCast(@constCast(&ready));
    if (stringNameEqual(name, &handle_input_name)) return @ptrCast(@constCast(&handleInput));
    if (stringNameEqual(name, &process_name)) return @ptrCast(@constCast(&process));

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

    if (userdata == @as(?*anyopaque, @ptrCast(@constCast(&process)))) {
        const delta: *const f64 = @ptrCast(@alignCast(args[0].?));
        process(self, delta.*);
        return;
    }
}
