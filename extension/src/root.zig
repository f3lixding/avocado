const godot = @import("godot_zig");

const SoftBody3D = godot.generated.classes.SoftBody3D;

var ready_tag: u8 = 0;
var physics_process_tag: u8 = 0;

const Avocado = struct {
    object: godot.c.GDExtensionObjectPtr,
    impulse_timer: f64,

    pub fn init(object: godot.c.GDExtensionObjectPtr) Avocado {
        return .{ .object = object, .impulse_timer = 0.0 };
    }

    fn asNode(self: *Avocado) godot.Node {
        return godot.Node.init(self.object);
    }

    fn asSoftBody(self: *Avocado) SoftBody3D {
        return SoftBody3D.init(self.object);
    }

    fn ready(self: *Avocado) callconv(.c) void {
        godot.log.errMsg("avocado", "READY RAN", .{
            .function = @src().fn_name,
            .file = @src().file,
            .line = @src().line,
            .editor_notify = true,
        });

        const node = self.asNode();
        node.set_physics_process(true);

        const soft_body = self.asSoftBody();
        soft_body.set_linear_stiffness(1.0);
        // soft_body.set_damping_coefficient(0.7);
        soft_body.set_drag_coefficient(0.1);
        soft_body.set_pressure_coefficient(40.0);
        soft_body.set_simulation_precision(5);
        soft_body.set_total_mass(1.0);

        godot.log.warnMsg("avocado", "soft body settings applied", .{
            .function = @src().fn_name,
            .file = @src().file,
            .line = @src().line,
            .editor_notify = true,
        });
    }

    fn physicsProcess(self: *Avocado, delta: f64) callconv(.c) void {
        self.impulse_timer += delta;
        if (self.impulse_timer < 2.0) return;
        self.impulse_timer = 0.0;

        godot.log.warnMsg("avocado", "applying impulse", .{
            .function = @src().fn_name,
            .file = @src().file,
            .line = @src().line,
            .editor_notify = true,
        });

        self.asSoftBody().apply_central_impulse(.{
            .x = 2.0,
            .y = 6.0,
            .z = 0.0,
        });
    }

    pub fn getVirtualCallData(_: ?*anyopaque, name: godot.c.GDExtensionConstStringNamePtr, _: u32) callconv(.c) ?*anyopaque {
        var ready_name = godot.api.godot.stringName("_ready");
        defer godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME, &ready_name);
        var physics_name = godot.api.godot.stringName("_physics_process");
        defer godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME, &physics_name);

        if (stringNameEqual(name, &ready_name)) return &ready_tag;
        if (stringNameEqual(name, &physics_name)) return &physics_process_tag;
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
        const self: *Avocado = @ptrCast(@alignCast(instance.?));

        if (userdata == @as(?*anyopaque, @ptrCast(&ready_tag))) {
            ready(self);
            return;
        }

        if (userdata == @as(?*anyopaque, @ptrCast(&physics_process_tag))) {
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

    godot.class.NativeClass(Avocado, "SoftBody3D", "Avocado").register();
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
