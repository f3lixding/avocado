const godot = @import("godot_zig");

const MeshInstance3D = godot.generated.classes.MeshInstance3D;
const Node = godot.generated.classes.Node;
const Mesh = godot.Mesh;

const SimulatedSurface = @import("util/SimulatedSurface.zig");
const log = @import("util/root.zig").log;

const JelloVisual = struct {
    object: godot.c.GDExtensionObjectPtr,
    simulated_surface: SimulatedSurface = .{},
    mouse_button_class: godot.StringName,

    pub fn init(object: godot.c.GDExtensionObjectPtr) JelloVisual {
        return .{
            .object = object,
            .mouse_button_class = godot.api.godot.stringName("InputEventMouseButton"),
        };
    }

    pub fn deinit(self: *JelloVisual) void {
        self.simulated_surface.deinit();
        godot.api.godot.destroy(
            godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME,
            &self.mouse_button_class,
        );
        log("deinit called");
    }

    fn ready(self: *JelloVisual) callconv(.c) void {
        const node = Node.init(self.object);
        node.set_process_input(true);
        node.set_physics_process(true);

        const visual = MeshInstance3D.init(self.object);

        self.simulated_surface.prime(&visual) catch {
            const message = "Error preparing simulated surface";
            log(message);
            @panic(message);
        };
    }

    fn physicsProcess(self: *JelloVisual, delta: f64) callconv(.c) void {
        self.simulated_surface.tick(delta) catch {
            log("Error updating simulated surface");
        };
    }

    fn handleInput(self: *JelloVisual, raw_event: godot.c.GDExtensionObjectPtr) callconv(.c) void {
        const Object = godot.generated.classes.Object;
        const InputEvent = godot.generated.classes.InputEvent;
        const InputEventMouseButton = godot.generated.classes.InputEventMouseButton;

        const object = Object.init(raw_event);
        if (!object.is_class(self.mouse_button_class)) return;

        const mouse = InputEventMouseButton.init(raw_event);
        if (mouse.get_button_index() != 1) return;

        const event = InputEvent.init(raw_event);
        if (!event.is_pressed()) return;

        // Temporary contact until mouse raycasting supplies real local data.
        self.simulated_surface.excite(.{
            .point_local = .{ .x = 0.5, .y = 0.5, .z = 0.0 },
            .normal_local = .{ .x = 1.0, .y = 1.0, .z = 0.0 },
            .strength = 4.0,
        });
    }

    pub fn getVirtualCallData(_: ?*anyopaque, name: godot.c.GDExtensionConstStringNamePtr, _: u32) callconv(.c) ?*anyopaque {
        var ready_name = godot.api.godot.stringName("_ready");
        defer godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME, &ready_name);
        var physics_name = godot.api.godot.stringName("_physics_process");
        defer godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME, &physics_name);
        var handle_input_name = godot.api.godot.stringName("_input");
        defer godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME, &handle_input_name);

        if (stringNameEqual(name, &ready_name)) return @ptrCast(@constCast(&ready));
        if (stringNameEqual(name, &physics_name)) return @ptrCast(@constCast(&physicsProcess));
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
        const self: *JelloVisual = @ptrCast(@alignCast(instance.?));

        if (userdata == @as(?*anyopaque, @ptrCast(@constCast(&ready)))) {
            ready(self);
            return;
        }

        if (userdata == @as(?*anyopaque, @ptrCast(@constCast(&physicsProcess)))) {
            const delta: *const f64 = @ptrCast(@alignCast(args[0].?));
            physicsProcess(self, delta.*);
            return;
        }

        if (userdata == @as(?*anyopaque, @ptrCast(@constCast(&handleInput)))) {
            const event_ptr: *const godot.c.GDExtensionObjectPtr = @ptrCast(@alignCast(args[0].?));
            handleInput(self, event_ptr.*);
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

    godot.class.NativeClass(JelloVisual, "MeshInstance3D", "JelloVisual").register();
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
