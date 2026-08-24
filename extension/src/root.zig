const godot = @import("godot_zig");

const JelloVisual = @import("JelloVisual.zig");
const Cursor = @import("Cursor.zig");

fn initialize(level: godot.c.GDExtensionInitializationLevel) callconv(.c) void {
    if (level != godot.c.GDEXTENSION_INITIALIZATION_SCENE) return;

    godot.class.NativeClass(JelloVisual, "MeshInstance3D", "JelloVisual").register();

    godot.class.NativeClass(Cursor, "RigidBody3D", "Cursor").register();
    godot.class.registerSignal("Cursor", Cursor.ContactSignal);
    godot.class.registerSignalHandler(
        JelloVisual,
        "JelloVisual",
        "on_contact_requested",
        Cursor.ContactSignal,
        &JelloVisual.onContactRequested,
    );
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
