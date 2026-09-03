const godot = @import("godot_zig");

const JelloVisual = @import("JelloVisual.zig");
const Cursor = @import("Cursor.zig");
const Character = @import("Character.zig");

var character_runtime_names: Character.RuntimeNames = undefined;
var character_runtime_names_initialized = false;

fn initialize(level: godot.c.GDExtensionInitializationLevel) callconv(.c) void {
    if (level != godot.c.GDEXTENSION_INITIALIZATION_SCENE) return;

    character_runtime_names = Character.RuntimeNames.init();
    character_runtime_names_initialized = true;

    godot.class.NativeClass(JelloVisual, "MeshInstance3D", "JelloVisual").register();

    godot.class.NativeClass(Cursor, "Node3D", "Cursor").register();
    godot.class.registerSignal("Cursor", Cursor.ContactSignal);
    godot.class.registerSignalHandler(
        JelloVisual,
        "JelloVisual",
        "on_contact_requested",
        Cursor.ContactSignal,
        &JelloVisual.onContactRequested,
    );

    godot.class.NativeClass(Character, "CharacterBody3D", "Character").registerWithUserdata(&character_runtime_names);
}

fn deinitialize(level: godot.c.GDExtensionInitializationLevel) callconv(.c) void {
    if (level != godot.c.GDEXTENSION_INITIALIZATION_SCENE) return;

    if (character_runtime_names_initialized) {
        character_runtime_names.deinit();
        character_runtime_names_initialized = false;
    }
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
