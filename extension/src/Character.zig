const std = @import("std");
const godot = @import("godot_zig");

const CharacterBody3D = godot.generated.classes.CharacterBody3D;
const CollisionObject3D = godot.generated.classes.CollisionObject3D;
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
const CameraAttributesPractical = godot.generated.classes.CameraAttributesPractical;
const AnimationTree = godot.generated.classes.AnimationTree;
const AnimationMixer = godot.generated.classes.AnimationMixer;
const AnimationNodeStateMachinePlayback = godot.generated.classes.AnimationNodeStateMachinePlayback;
const AnimationNodeOneShot = godot.generated.classes.AnimationNodeOneShot;

const util = @import("util/root.zig");
const stringNameEqual = util.stringNameEqual;

const Self = @This();

pub const RuntimeNames = struct {
    move_left: godot.StringName,
    move_right: godot.StringName,
    move_forward: godot.StringName,
    move_backward: godot.StringName,
    jump: godot.StringName,
    shift: godot.StringName,
    aim: godot.StringName,
    input_event_mouse_motion: godot.StringName,

    // Animation tree param names
    anim_tree_path: godot.NodePath,
    movement_playback_param: godot.StringName,
    locomotion_param: godot.StringName,
    pistol_aim_param: godot.StringName,
    aim_blend_param: godot.StringName,
    // Animation tree states
    state_locomotion: godot.StringName,
    state_sprint_enter: godot.StringName,
    state_sprint: godot.StringName,
    sprint_exit_oneshot: godot.StringName,
    state_jump_start: godot.StringName,
    state_jump: godot.StringName,
    jump_land_oneshot: godot.StringName,

    ready: godot.StringName,
    input: godot.StringName,
    process: godot.StringName,
    physics_process: godot.StringName,
    camera_pivot_path: godot.NodePath,
    spring_arm_path: godot.NodePath,
    camera_shake_node_path: godot.NodePath,
    camera_path: godot.NodePath,

    pub fn init() RuntimeNames {
        return .{
            .move_left = godot.api.godot.stringName("move_left"),
            .move_right = godot.api.godot.stringName("move_right"),
            .move_forward = godot.api.godot.stringName("move_forward"),
            .move_backward = godot.api.godot.stringName("move_backward"),
            .jump = godot.api.godot.stringName("jump"),
            .shift = godot.api.godot.stringName("shift"),
            .aim = godot.api.godot.stringName("aim"),
            .input_event_mouse_motion = godot.api.godot.stringName("InputEventMouseMotion"),

            .anim_tree_path = godot.api.godot.nodePath("UAL1/AnimationTree"),
            .movement_playback_param = godot.api.godot.stringName("parameters/StateMachine/playback"),
            .locomotion_param = godot.api.godot.stringName("parameters/StateMachine/Locomotion/blend_position"),
            .pistol_aim_param = godot.api.godot.stringName("parameters/PistolAim/blend_position"),
            .aim_blend_param = godot.api.godot.stringName("parameters/AimBlend/blend_amount"),

            .state_locomotion = godot.api.godot.stringName("Locomotion"),
            .state_sprint_enter = godot.api.godot.stringName("Sprint_Enter"),
            .state_sprint = godot.api.godot.stringName("Sprint"),
            .sprint_exit_oneshot = godot.api.godot.stringName("parameters/SprintExitOneShot/request"),
            .state_jump_start = godot.api.godot.stringName("Jump_Start"),
            .state_jump = godot.api.godot.stringName("Jump"),
            .jump_land_oneshot = godot.api.godot.stringName("parameters/JumpLandOneShot/request"),

            .ready = godot.api.godot.stringName("_ready"),
            .input = godot.api.godot.stringName("_input"),
            .process = godot.api.godot.stringName("_process"),
            .physics_process = godot.api.godot.stringName("_physics_process"),
            .camera_pivot_path = godot.api.godot.nodePath("CameraPivot"),
            .spring_arm_path = godot.api.godot.nodePath("CameraPivot/SpringArm3D"),
            .camera_shake_node_path = godot.api.godot.nodePath("CameraPivot/SpringArm3D/CameraShake"),
            .camera_path = godot.api.godot.nodePath("CameraPivot/SpringArm3D/CameraShake/Camera3D"),
        };
    }

    pub fn deinit(self: *RuntimeNames) void {
        godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME, &self.move_left);
        godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME, &self.move_right);
        godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME, &self.move_forward);
        godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME, &self.move_backward);
        godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME, &self.jump);
        godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME, &self.shift);
        godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME, &self.aim);
        godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME, &self.input_event_mouse_motion);

        godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_NODE_PATH, &self.anim_tree_path);
        godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME, &self.movement_playback_param);
        godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME, &self.locomotion_param);
        godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME, &self.pistol_aim_param);
        godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME, &self.aim_blend_param);

        godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME, &self.state_locomotion);
        godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME, &self.state_sprint_enter);
        godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME, &self.state_sprint);
        godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME, &self.sprint_exit_oneshot);
        godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME, &self.state_jump_start);
        godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME, &self.state_jump);
        godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME, &self.jump_land_oneshot);

        godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME, &self.ready);
        godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME, &self.input);
        godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME, &self.process);
        godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME, &self.physics_process);
        godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_NODE_PATH, &self.camera_pivot_path);
        godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_NODE_PATH, &self.spring_arm_path);
        godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_NODE_PATH, &self.camera_shake_node_path);
        godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_NODE_PATH, &self.camera_path);
    }
};

pub const AnimState = enum(i64) {
    locomotion = 0,
    sprint_enter,
    sprint,
    jump_start,
    jump,
};

object: godot.c.GDExtensionObjectPtr,
names: *RuntimeNames,
animation_tree: ?AnimationTree = null,
animation_playback: ?AnimationNodeStateMachinePlayback = null,
was_sprinting: bool = false,
pending_landing_shake: f64 = 0.0,
locomotion_blend: Vector2 = .{},
aim_weight: f32 = 0.0,
// updated for process to use for aim
x_view_angle: f32 = 0.0,
// Replicated animation state and event sequences.
anim_state: AnimState = .locomotion,
landing_sequence: i64 = 0,
sprint_exit_sequence: i64 = 0,

spring_arm: ?SpringArm3D = null,
camera_pivot: ?Node3D = null,
camera: ?Camera3D = null,
camera_attr_practical: ?CameraAttributesPractical = null,
camera_fov: struct {
    setting: f32 = 0,
    current: f32 = 0,
    target: f32 = 0,
} = .{},
camera_shake_node: ?Node3D = null,
camera_shake_time: f32 = 0.0,
camera_shake_strength: f32 = 0.0,

local_input_enabled: bool = false,

const TOP_SPRINT_SPEED: f32 = 20.0;
const SPRINT_SPEED_THRESHOLD: f32 = 15.0;
const ACCELERATION: f32 = 10.0;
const AIR_CONTROL: f32 = 0.35;
const JUMP_VELOCITY: f32 = 5.0;
const GRAVITY: f32 = 9.8;
const TERMINAL_VELOCITY: f32 = 50.0;
const MOUSE_SENSITIVITY: f64 = 0.0025;
const MINIMUM_PITCH: f64 = -60.0;
const MAXIMUM_PITCH: f64 = 45.0;
const JUMP_DISTURBANCE_DURATION: f64 = 0.5;

pub fn initWithUserdata(object: godot.c.GDExtensionObjectPtr, class_userdata: ?*anyopaque) Self {
    const names: *RuntimeNames = @ptrCast(@alignCast(class_userdata.?));
    return .{
        .object = object,
        .names = names,
    };
}

pub fn deinit(self: *Self) void {
    if (self.camera_attr_practical) |attr| {
        const RefCounted = godot.generated.classes.RefCounted;
        _ = RefCounted.init(attr.asObject().ptr).unreference();
        self.camera_attr_practical = null;
    }
}

pub fn ready(self: *Self) callconv(.c) void {
    if (Engine.singleton().is_editor_hint()) return;

    const node = Node.init(self.object);
    const multiplayer = node.get_multiplayer();
    defer {
        const RefCounted = godot.generated.classes.RefCounted;
        _ = RefCounted.init(multiplayer.asObject().ptr).unreference();
    }

    self.local_input_enabled = multiplayer.get_unique_id() == node.get_multiplayer_authority();

    node.set_physics_process(self.local_input_enabled);
    node.set_process_input(self.local_input_enabled);
    node.set_process(self.local_input_enabled);

    if (self.local_input_enabled) {
        const input = Input.singleton();
        input.set_mouse_mode(Input.MouseMode.captured);
    }

    const camera_pivot_node = node.get_node(self.names.camera_pivot_path);
    const spring_arm_node = node.get_node(self.names.spring_arm_path);
    const camera_shake_node = node.get_node(self.names.camera_shake_node_path);
    const camera_node = node.get_node(self.names.camera_path);
    if (!camera_pivot_node.isNull() and !spring_arm_node.isNull() and !camera_shake_node.isNull() and !camera_node.isNull()) {
        self.camera_pivot = Node3D.init(camera_pivot_node.object.ptr);
        self.spring_arm = SpringArm3D.init(spring_arm_node.object.ptr);
        self.camera_shake_node = Node3D.init(camera_shake_node.object.ptr);
        self.camera = Camera3D.init(camera_node.object.ptr);

        self.camera.?.set_current(self.local_input_enabled);

        // Never let the spring arm retract because it hit its own character.
        const character_collision = CollisionObject3D.init(self.object);
        self.spring_arm.?.add_excluded_object(character_collision.get_rid());
        const initial_fov: f32 = @floatCast(self.camera.?.get_fov());
        self.camera_fov = .{
            .current = initial_fov,
            .setting = initial_fov,
            .target = initial_fov,
        };

        // dof blur
        const camera_attr = self.camera.?.get_attributes();
        if (!camera_attr.isNull()) {
            self.camera_attr_practical = CameraAttributesPractical.init(camera_attr.asObject().ptr);
            self.camera_attr_practical.?.set_dof_blur_near_distance(10.0);
            self.camera_attr_practical.?.set_dof_blur_near_transition(5.0);
            self.camera_attr_practical.?.set_dof_blur_amount(0.2);
            self.camera_attr_practical.?.set_dof_blur_near_enabled(false);
        } else {
            const msg = "Failed to retrieve camera practical attr";
            util.log(msg);
            @panic(msg);
        }
    } else {
        util.log("camera rig node is null");
    }

    const anim_tree_node = node.get_node(self.names.anim_tree_path);
    if (!anim_tree_node.isNull()) {
        const anim_tree = AnimationTree.init(anim_tree_node.asObject().ptr);

        // Because zig has no inheritance so we have to go directly to the underlying method
        AnimationMixer.init(anim_tree_node.asObject().ptr).set_active(true);

        var playback_variant = anim_tree.asObject().get(self.names.movement_playback_param);
        defer playback_variant.destroy();
        const pbv_ptr = playback_variant.toObjectPtr();
        if (pbv_ptr) |ptr| {
            const playback = AnimationNodeStateMachinePlayback.init(ptr);
            playback.start(self.names.state_locomotion, true);

            anim_tree.asObject().set(
                self.names.locomotion_param,
                Vector2{
                    .x = 0.0,
                    .y = 0.0,
                },
            );

            self.animation_tree = anim_tree;
            self.animation_playback = playback;
        } else {
            const msg = "Playback variant ptr is null";
            util.log(msg);
            @panic(msg);
        }
    } else {
        const msg = "AnimationTree node is null";
        util.log(msg);
        @panic(msg);
    }
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
    const min_pitch_rad: f64 = std.math.degreesToRadians(MINIMUM_PITCH);
    const max_pitch_rad: f64 = std.math.degreesToRadians(MAXIMUM_PITCH);
    const x_rotation = std.math.clamp(
        @as(f64, rotation.x) - @as(f64, relative.y) * MOUSE_SENSITIVITY,
        min_pitch_rad,
        max_pitch_rad,
    );
    rotation.x = @floatCast(x_rotation);
    camera_pivot.set_rotation(rotation);

    self.x_view_angle = @floatCast(if (x_rotation < 0.0)
        x_rotation / -min_pitch_rad
    else
        x_rotation / max_pitch_rad);
}

pub fn physicsProcess(self: *Self, delta: f64) callconv(.c) void {
    if (Engine.singleton().is_editor_hint()) return;

    const input = Input.singleton();
    const body = CharacterBody3D.init(self.object);
    const is_on_floor = body.is_on_floor();
    const is_shift_held = input.is_action_pressed(self.names.shift, false);

    var x: f32 = 0.0;
    var z: f32 = 0.0;
    if (input.is_action_pressed(self.names.move_left, false)) x -= 1.0;
    if (input.is_action_pressed(self.names.move_right, false)) x += 1.0;
    if (input.is_action_pressed(self.names.move_forward, false)) z -= 1.0;
    if (input.is_action_pressed(self.names.move_backward, false)) z += 1.0;

    const input_length = @sqrt(x * x + z * z);
    const has_movement_input = input_length > 0.0;
    if (has_movement_input) {
        x /= input_length;
        z /= input_length;
    }

    const direction = self.cameraRelativeDirection(.{ .x = x, .y = z });
    var velocity = body.get_velocity();
    var should_sprint = is_on_floor and has_movement_input and is_shift_held;

    const control: f32 = if (is_on_floor) 3.0 else AIR_CONTROL;
    const step = ACCELERATION * control * @as(f32, @floatCast(delta));
    const top_speed = if (should_sprint) TOP_SPRINT_SPEED else SPRINT_SPEED_THRESHOLD;
    velocity.x = moveToward(velocity.x, direction.x * top_speed, step);
    velocity.z = moveToward(velocity.z, direction.z * top_speed, step);

    var jumped = false;
    if (is_on_floor) {
        if (input.is_action_just_pressed(self.names.jump, false)) {
            velocity.y = JUMP_VELOCITY;
            jumped = true;
        } else if (velocity.y < 0.0) {
            velocity.y = 0.0;
        }
    } else {
        velocity.y = @max(
            velocity.y - GRAVITY * @as(f32, @floatCast(delta)),
            -TERMINAL_VELOCITY,
        );
    }

    if (has_movement_input or jumped) {
        self.animation_tree.?.asObject().set(self.names.sprint_exit_oneshot, @as(i64, AnimationNodeOneShot.OneShotRequest.fade_out));
        self.animation_tree.?.asObject().set(self.names.jump_land_oneshot, @as(i64, AnimationNodeOneShot.OneShotRequest.fade_out));
    }

    self.updateCameraFov(velocity);

    body.set_velocity(velocity);
    _ = body.move_and_slide();

    const now_on_floor = body.is_on_floor();
    const now_velocity = body.get_velocity();
    const horizontal_speed = @sqrt(now_velocity.x * now_velocity.x + now_velocity.z * now_velocity.z);

    const just_landed = !is_on_floor and now_on_floor;

    if (just_landed)
        self.pending_landing_shake = JUMP_DISTURBANCE_DURATION;

    should_sprint = now_on_floor and has_movement_input and is_shift_held;

    const jog_weight = std.math.clamp(
        horizontal_speed / SPRINT_SPEED_THRESHOLD,
        0.0,
        1.0,
    );

    const target_blend = Vector2{
        .x = x * jog_weight,
        .y = -z * jog_weight,
    };
    const max_blend_delta = step / SPRINT_SPEED_THRESHOLD;

    self.locomotion_blend.x = moveToward(
        self.locomotion_blend.x,
        target_blend.x,
        max_blend_delta,
    );
    self.locomotion_blend.y = moveToward(
        self.locomotion_blend.y,
        target_blend.y,
        max_blend_delta,
    );
    self.animation_tree.?.asObject().set(self.names.locomotion_param, self.locomotion_blend);

    if (jumped) {
        self.setAnimationState(@intFromEnum(AnimState.jump_start));
    } else if (just_landed) {
        self.setAnimationState(@intFromEnum(AnimState.locomotion));
        self.setLandingSequence(self.landing_sequence + 1);
    } else if (should_sprint and !self.was_sprinting) {
        self.setAnimationState(@intFromEnum(AnimState.sprint_enter));
    } else if (!should_sprint and self.was_sprinting) {
        self.setAnimationState(@intFromEnum(AnimState.locomotion));
        self.setSprintExitSequence(self.sprint_exit_sequence + 1);
    }

    self.was_sprinting = should_sprint;
}

pub fn process(self: *Self, delta: f64) callconv(.c) void {
    if (Engine.singleton().is_editor_hint()) return;

    const input = Input.singleton();
    const is_aiming = input.is_action_pressed(self.names.aim, false);

    self.camera_attr_practical.?.set_dof_blur_near_enabled(is_aiming);

    const camera = self.camera orelse return;
    const max_delta = if (is_aiming or self.camera_fov.current < self.camera_fov.setting)
        500.0 * @as(f32, @floatCast(delta))
    else
        40.0 * @as(f32, @floatCast(delta));
    const new_fov = moveToward(
        self.camera_fov.current,
        if (is_aiming) 30.0 else self.camera_fov.target,
        max_delta,
    );
    if (new_fov != self.camera_fov.current) {
        self.camera_fov.current = new_fov;
        camera.set_fov(@floatCast(new_fov));
    }

    const body = CharacterBody3D.init(self.object);
    const velocity = body.get_velocity();
    const horizontal_speed = @sqrt(
        velocity.x * velocity.x + velocity.z * velocity.z,
    );
    const shake_target = blk: {
        if (self.was_sprinting) break :blk std.math.clamp(horizontal_speed / TOP_SPRINT_SPEED, 0.0, 1.0);

        if (self.pending_landing_shake > 0.0) {
            self.pending_landing_shake = @max(self.pending_landing_shake - delta, 0.0);
            break :blk 0.5;
        }

        break :blk 0.0;
    };

    self.disturbCamera(@floatCast(delta), shake_target);

    const target_aim_weight: f32 = blk: {
        if (is_aiming) {
            self.animation_tree.?.asObject().set(
                self.names.pistol_aim_param,
                self.x_view_angle,
            );
            break :blk 1.0;
        }
        break :blk 0.0;
    };

    self.aim_weight = moveToward(self.aim_weight, target_aim_weight, 8.0 * @as(f32, @floatCast(delta)));
    self.animation_tree.?.asObject().set(self.names.aim_blend_param, self.aim_weight);
}

pub fn setAnimationState(self: *Self, value: i64) callconv(.c) void {
    const state: AnimState = switch (value) {
        0 => .locomotion,
        1 => .sprint_enter,
        2 => .sprint,
        3 => .jump_start,
        4 => .jump,
        else => return,
    };
    if (state == self.anim_state) return;

    self.anim_state = state;
    const playback = self.animation_playback orelse return;
    const name = switch (state) {
        .locomotion => self.names.state_locomotion,
        .sprint_enter => self.names.state_sprint_enter,
        .sprint => self.names.state_sprint,
        .jump_start => self.names.state_jump_start,
        .jump => self.names.state_jump,
    };

    if (state == .jump_start) {
        playback.travel(name, true);
    } else {
        playback.start(name, true);
    }
}

pub fn getAnimationState(self: *Self) callconv(.c) i64 {
    return @intFromEnum(self.anim_state);
}

pub fn setLandingSequence(self: *Self, value: i64) callconv(.c) void {
    if (value == self.landing_sequence) return;
    self.landing_sequence = value;

    const tree = self.animation_tree orelse return;
    tree.asObject().set(
        self.names.jump_land_oneshot,
        @as(i64, AnimationNodeOneShot.OneShotRequest.fire),
    );
}

pub fn getLandingSequence(self: *Self) callconv(.c) i64 {
    return self.landing_sequence;
}

pub fn setSprintExitSequence(self: *Self, value: i64) callconv(.c) void {
    if (value == self.sprint_exit_sequence) return;
    self.sprint_exit_sequence = value;

    const tree = self.animation_tree orelse return;
    tree.asObject().set(
        self.names.sprint_exit_oneshot,
        @as(i64, AnimationNodeOneShot.OneShotRequest.fire),
    );
}

pub fn getSprintExitSequence(self: *Self) callconv(.c) i64 {
    return self.sprint_exit_sequence;
}

fn updateCameraFov(self: *Self, velocity: Vector3) void {
    // Ignore vertical velocity so jumping and falling do not alter the FOV.
    const horizontal_speed = @sqrt(
        velocity.x * velocity.x + velocity.z * velocity.z,
    );

    const speed_ratio = std.math.clamp(horizontal_speed / TOP_SPRINT_SPEED, 0.0, 1.0);
    self.camera_fov.target = self.camera_fov.setting + 20.0 * speed_ratio;
}

fn disturbCamera(self: *Self, delta: f32, target_strength: f32) void {
    const SHAKE_ATTACK: f32 = 8.0;
    const SHAKE_DECAY: f32 = 1.8;
    const SHAKE_FREQUENCY: f32 = 5.0;
    const MAX_POSITION_SHAKE: f32 = 0.025;
    const MAX_PITCH_SHAKE: f32 = std.math.degreesToRadians(0.5);
    const MAX_YAW_SHAKE: f32 = std.math.degreesToRadians(0.5);
    const MAX_ROLL_SHAKE: f32 = std.math.degreesToRadians(0.5);
    const TAU: f32 = 2.0 * std.math.pi;

    const node = self.camera_shake_node orelse return;
    self.camera_shake_time += delta;

    const rate = if (target_strength > self.camera_shake_strength)
        SHAKE_ATTACK
    else
        SHAKE_DECAY;
    self.camera_shake_strength = moveToward(
        self.camera_shake_strength,
        std.math.clamp(target_strength, 0.0, 1.0),
        rate * delta,
    );

    // Squaring gives weak shakes a softer response while preserving the peak.
    const strength = self.camera_shake_strength * self.camera_shake_strength;
    const phase = self.camera_shake_time * TAU * SHAKE_FREQUENCY;

    const position_x = @sin(phase * 1.07 + 0.4);
    const position_y = @sin(phase * 0.83 + 1.7);
    const pitch = @sin(phase * 1.19 + 2.3);
    const yaw = @sin(phase * 0.91 + 3.1);
    const roll = @sin(phase * 1.31 + 4.2);

    var position = node.get_position();
    position.x = position_x * MAX_POSITION_SHAKE * strength;
    position.y = position_y * MAX_POSITION_SHAKE * strength;
    node.set_position(position);
    node.set_rotation(.{
        .x = pitch * MAX_PITCH_SHAKE * strength,
        .y = yaw * MAX_YAW_SHAKE * strength,
        .z = roll * MAX_ROLL_SHAKE * strength,
    });
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

pub fn getVirtualCallData(
    class_userdata: ?*anyopaque,
    name: godot.c.GDExtensionConstStringNamePtr,
    _: u32,
) callconv(.c) ?*anyopaque {
    const names: *RuntimeNames = @ptrCast(@alignCast(class_userdata.?));
    if (stringNameEqual(name, &names.ready)) return @ptrCast(@constCast(&ready));
    if (stringNameEqual(name, &names.input)) return @ptrCast(@constCast(&handleInput));
    if (stringNameEqual(name, &names.process)) return @ptrCast(@constCast(&process));
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
    } else if (userdata == @as(?*anyopaque, @ptrCast(@constCast(&process)))) {
        const delta: *const f64 = @ptrCast(@alignCast(args[0].?));
        process(self, delta.*);
    } else if (userdata == @as(?*anyopaque, @ptrCast(@constCast(&physicsProcess)))) {
        const delta: *const f64 = @ptrCast(@alignCast(args[0].?));
        physicsProcess(self, delta.*);
    }
}
