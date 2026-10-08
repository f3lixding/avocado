const godot = @import("godot_zig");

const JelloVisual = @import("JelloVisual.zig");
const Cursor = @import("Cursor.zig");
const Character = @import("Character.zig");
const SpineYawModifier = @import("SpineYawModifier.zig");
const Sword = @import("Sword.zig");

var character_runtime_names: Character.RuntimeNames = undefined;
var sword_runtime_names: Sword.RuntimeNames = undefined;

fn initialize(level: godot.c.GDExtensionInitializationLevel) callconv(.c) void {
    if (level != godot.c.GDEXTENSION_INITIALIZATION_SCENE) return;

    character_runtime_names = Character.RuntimeNames.init();
    sword_runtime_names = Sword.RuntimeNames.init();

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

    godot.class.NativeClass(SpineYawModifier, "SkeletonModifier3D", "SpineYawModifier").register();
    godot.class.registerProperty(
        SpineYawModifier,
        "SpineYawModifier",
        "yaw",
        .float,
        SpineYawModifier.getYaw,
        SpineYawModifier.setYaw,
    );

    godot.class.NativeClass(Character, "CharacterBody3D", "Character").registerWithUserdata(&character_runtime_names);
    godot.class.registerProperty(
        Character,
        "Character",
        "animation_state",
        .int,
        Character.getAnimationState,
        Character.setLocoState,
    );
    godot.class.registerProperty(
        Character,
        "Character",
        "landing_sequence",
        .int,
        Character.getLandingSequence,
        Character.setLandingSequence,
    );
    godot.class.registerProperty(
        Character,
        "Character",
        "sprint_exit_sequence",
        .int,
        Character.getSprintExitSequence,
        Character.setSprintExitSequence,
    );
    godot.class.registerMethod1(
        Character,
        "Character",
        "set_trail_enabled",
        .bool,
        Character.setTrailEnabled,
    );

    godot.class.NativeClass(Sword, "Node3D", "Sword").registerWithUserdata(&sword_runtime_names);
}

fn deinitialize(level: godot.c.GDExtensionInitializationLevel) callconv(.c) void {
    if (level != godot.c.GDEXTENSION_INITIALIZATION_SCENE) return;

    character_runtime_names.deinit();
    sword_runtime_names.deinit();
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
