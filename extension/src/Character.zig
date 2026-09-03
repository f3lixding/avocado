const std = @import("std");
const godot = @import("godot_zig");

const CharacterBody3D = godot.generated.classes.CharacterBody3D;
const Engine = godot.generated.classes.Engine;
const Input = godot.generated.classes.Input;
const InputMap = godot.generated.classes.InputMap;
const InputEventMouseMotion = godot.generated.classes.InputEventMouseMotion;
const Node = godot.generated.classes.Node;
const Node3D = godot.generated.classes.Node3D;
const Object = godot.generated.classes.Object;
const Vector2 = godot.Vector2;
const Vector3 = godot.Vector3;
const SpringArm3D = godot.generated.classes.SpringArm3D;
const Camera3D = godot.generated.classes.Camera3D;
const AnimationPlayer = godot.generated.classes.AnimationPlayer;

const util = @import("util/root.zig");
const stringNameEqual = util.stringNameEqual;

const Self = @This();

pub const RuntimeNames = struct {
    move_left: godot.StringName,
    move_right: godot.StringName,
    move_forward: godot.StringName,
    move_backward: godot.StringName,
    jump: godot.StringName,
    input_event_mouse_motion: godot.StringName,
    anim_name: godot.StringName,
    ready: godot.StringName,
    input: godot.StringName,
    physics_process: godot.StringName,
    animation_player_path: godot.NodePath,
    camera_pivot_path: godot.NodePath,
    spring_arm_path: godot.NodePath,
    camera_path: godot.NodePath,

    pub fn init() RuntimeNames {
        return .{
            .move_left = godot.api.godot.stringName("move_left"),
            .move_right = godot.api.godot.stringName("move_right"),
            .move_forward = godot.api.godot.stringName("move_forward"),
            .move_backward = godot.api.godot.stringName("move_backward"),
            .jump = godot.api.godot.stringName("jump"),
            .input_event_mouse_motion = godot.api.godot.stringName("InputEventMouseMotion"),
            .anim_name = godot.api.godot.stringName("Jog_Fwd"),
            .ready = godot.api.godot.stringName("_ready"),
            .input = godot.api.godot.stringName("_input"),
            .physics_process = godot.api.godot.stringName("_physics_process"),
            .animation_player_path = godot.api.godot.nodePath("UAL1/AnimationPlayer"),
            .camera_pivot_path = godot.api.godot.nodePath("CameraPivot"),
            .spring_arm_path = godot.api.godot.nodePath("CameraPivot/SpringArm3D"),
            .camera_path = godot.api.godot.nodePath("CameraPivot/SpringArm3D/Camera3D"),
        };
    }

    pub fn deinit(self: *RuntimeNames) void {
        godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME, &self.move_left);
        godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME, &self.move_right);
        godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME, &self.move_forward);
        godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME, &self.move_backward);
        godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME, &self.jump);
        godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME, &self.input_event_mouse_motion);
        godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME, &self.anim_name);
        godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME, &self.ready);
        godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME, &self.input);
        godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME, &self.physics_process);
        godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_NODE_PATH, &self.animation_player_path);
        godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_NODE_PATH, &self.camera_pivot_path);
        godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_NODE_PATH, &self.spring_arm_path);
        godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_NODE_PATH, &self.camera_path);
    }
};

object: godot.c.GDExtensionObjectPtr,
names: *RuntimeNames,
animation_player: ?AnimationPlayer = null,

spring_arm: ?SpringArm3D = null,
camera_pivot: ?Node3D = null,
camera: ?Camera3D = null,

const MOVE_SPEED: f32 = 5.0;
const ACCELERATION: f32 = 20.0;
const AIR_CONTROL: f32 = 0.35;
const JUMP_VELOCITY: f32 = 5.0;
const GRAVITY: f32 = 9.8;
const TERMINAL_VELOCITY: f32 = 50.0;
const MOUSE_SENSITIVITY: f64 = 0.0025;
const MINIMUM_PITCH: f64 = -60.0;
const MAXIMUM_PITCH: f64 = 45.0;

pub fn initWithUserdata(object: godot.c.GDExtensionObjectPtr, class_userdata: ?*anyopaque) Self {
    const names: *RuntimeNames = @ptrCast(@alignCast(class_userdata.?));
    return .{
        .object = object,
        .names = names,
    };
}

pub fn deinit(_: *Self) void {}

pub fn ready(self: *Self) callconv(.c) void {
    if (Engine.singleton().is_editor_hint()) return;

    self.ensureInputActionsExist();

    const node = Node.init(self.object);
    node.set_physics_process(true);
    node.set_process_input(true);

    const camera_pivot_node = node.get_node(self.names.camera_pivot_path);
    const spring_arm_node = node.get_node(self.names.spring_arm_path);
    const camera_node = node.get_node(self.names.camera_path);
    if (!camera_pivot_node.isNull() and !spring_arm_node.isNull() and !camera_node.isNull()) {
        self.camera_pivot = Node3D.init(camera_pivot_node.object.ptr);
        self.spring_arm = SpringArm3D.init(spring_arm_node.object.ptr);
        self.camera = Camera3D.init(camera_node.object.ptr);
    } else {
        util.log("camera rig node is null");
    }

    const animation_player_node = node.get_node(self.names.animation_player_path);
    if (!animation_player_node.isNull()) {
        self.animation_player = AnimationPlayer.init(animation_player_node.object.ptr);
    } else {
        util.log("animation_player_node is null");
    }

    const input = Input.singleton();
    input.set_mouse_mode(Input.MouseMode.captured);
}

pub fn handleInput(self: *Self, raw_event: godot.c.GDExtensionObjectPtr) callconv(.c) void {
    if (Engine.singleton().is_editor_hint()) return;

    const object = Object.init(raw_event);
    if (!object.is_class(self.names.input_event_mouse_motion) or Input.singleton().get_mouse_mode() != Input.MouseMode.captured) return;

    const motion = InputEventMouseMotion.init(raw_event);
    const relative = motion.get_relative();
    const self_node = Node3D.init(self.object);
    self_node.rotate_y(-@as(f64, relative.x) * MOUSE_SENSITIVITY);

    const camera_pivot = self.camera_pivot orelse return;
    var rotation = camera_pivot.get_rotation();
    rotation.x = @floatCast(std.math.clamp(
        @as(f64, rotation.x) - @as(f64, relative.y) * MOUSE_SENSITIVITY,
        std.math.degreesToRadians(MINIMUM_PITCH),
        std.math.degreesToRadians(MAXIMUM_PITCH),
    ));
    camera_pivot.set_rotation(rotation);
}

pub fn physicsProcess(self: *Self, delta: f64) callconv(.c) void {
    if (Engine.singleton().is_editor_hint()) return;

    const input = Input.singleton();
    const body = CharacterBody3D.init(self.object);

    var x: f32 = 0.0;
    var z: f32 = 0.0;
    if (input.is_action_pressed(self.names.move_left, false)) x -= 1.0;
    if (input.is_action_pressed(self.names.move_right, false)) x += 1.0;
    if (input.is_action_pressed(self.names.move_forward, false)) z -= 1.0;
    if (input.is_action_pressed(self.names.move_backward, false)) z += 1.0;

    const length = @sqrt(x * x + z * z);
    const has_movement_input = length > 0.0;
    if (has_movement_input) {
        x /= length;
        z /= length;
    }

    self.updateAnimation(has_movement_input and body.is_on_floor());

    const direction = self.cameraRelativeDirection(.{ .x = x, .y = z });

    var velocity = body.get_velocity();
    const control: f32 = if (body.is_on_floor()) 1.0 else AIR_CONTROL;
    const step: f32 = ACCELERATION * control * @as(f32, @floatCast(delta));

    velocity.x = moveToward(velocity.x, direction.x * MOVE_SPEED, step);
    velocity.z = moveToward(velocity.z, direction.z * MOVE_SPEED, step);

    if (body.is_on_floor()) {
        if (input.is_action_just_pressed(self.names.jump, false)) {
            velocity.y = JUMP_VELOCITY;
        } else if (velocity.y < 0.0) {
            velocity.y = 0.0;
        }
    } else {
        velocity.y = @max(velocity.y - GRAVITY * @as(f32, @floatCast(delta)), -TERMINAL_VELOCITY);
    }

    body.set_velocity(velocity);
    _ = body.move_and_slide();
}

fn ensureInputActionsExist(self: *Self) void {
    const input_map = InputMap.singleton();
    if (!input_map.has_action(self.names.move_left)) input_map.add_action(self.names.move_left, 0.5);
    if (!input_map.has_action(self.names.move_right)) input_map.add_action(self.names.move_right, 0.5);
    if (!input_map.has_action(self.names.move_forward)) input_map.add_action(self.names.move_forward, 0.5);
    if (!input_map.has_action(self.names.move_backward)) input_map.add_action(self.names.move_backward, 0.5);
    if (!input_map.has_action(self.names.jump)) input_map.add_action(self.names.jump, 0.5);
}

fn updateAnimation(self: *Self, should_walk: bool) void {
    const player = self.animation_player orelse return;

    if (should_walk) {
        if (!player.is_playing()) {
            player.play(self.names.anim_name, -1.0, 1.0, false);
        }
    } else if (player.is_playing()) {
        player.stop(false);
    }
}

fn basisColumnX(basis: godot.Basis) Vector3 {
    return .{
        .x = basis.rows[0].x,
        .y = basis.rows[1].x,
        .z = basis.rows[2].x,
    };
}

fn basisColumnZ(basis: godot.Basis) Vector3 {
    return .{
        .x = basis.rows[0].z,
        .y = basis.rows[1].z,
        .z = basis.rows[2].z,
    };
}

fn moveToward(current: f32, target: f32, max_delta: f32) f32 {
    if (@abs(target - current) <= max_delta) return target;
    return current + std.math.sign(target - current) * max_delta;
}

// `input.x` is left/right. `input.y` is forward/backward, where forward is -1.
fn cameraRelativeDirection(self: *Self, input: Vector2) Vector3 {
    const camera = self.camera orelse {
        const fallback = Vector3{ .x = input.x, .y = 0.0, .z = input.y };
        return fallback.normalized();
    };

    const camera_node = Node3D.init(camera.asObject().ptr);
    const basis = camera_node.get_global_basis();

    var right = basisColumnX(basis);
    right.y = 0.0;
    right = right.normalized();

    var forward = basisColumnZ(basis);
    forward.x = -forward.x;
    forward.y = 0.0;
    forward.z = -forward.z;
    forward = forward.normalized();

    const direction = Vector3{
        .x = right.x * input.x + forward.x * -input.y,
        .y = 0.0,
        .z = right.z * input.x + forward.z * -input.y,
    };
    return direction.normalized();
}

pub fn getVirtualCallData(class_userdata: ?*anyopaque, name: godot.c.GDExtensionConstStringNamePtr, _: u32) callconv(.c) ?*anyopaque {
    const names: *RuntimeNames = @ptrCast(@alignCast(class_userdata.?));
    if (stringNameEqual(name, &names.ready)) return @ptrCast(@constCast(&ready));
    if (stringNameEqual(name, &names.input)) return @ptrCast(@constCast(&handleInput));
    if (stringNameEqual(name, &names.physics_process)) return @ptrCast(@constCast(&physicsProcess));
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
    } else if (userdata == @as(?*anyopaque, @ptrCast(@constCast(&handleInput)))) {
        const event_ptr: *const godot.c.GDExtensionObjectPtr = @ptrCast(@alignCast(args[0].?));
        handleInput(self, event_ptr.*);
    } else if (userdata == @as(?*anyopaque, @ptrCast(@constCast(&physicsProcess)))) {
        const delta: *const f64 = @ptrCast(@alignCast(args[0].?));
        physicsProcess(self, delta.*);
    }
}
