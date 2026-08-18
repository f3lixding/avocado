const std = @import("std");
const godot = @import("godot_zig");

const Vector3 = godot.Vector3;
const ArrayMesh = godot.generated.classes.ArrayMesh;

pub fn log(message: [*:0]const u8) void {
    godot.log.errMsg("avocado", message, .{
        .function = @src().fn_name,
        .file = @src().file,
        .line = @src().line,
        .editor_notify = false,
    });
}

pub fn logStringName(name: godot.StringName) void {
    var raw_variant: godot.types.Variant = std.mem.zeroes(godot.types.Variant);
    const make_variant = godot.api.godot.get_variant_from_type_constructor.?(
        godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME,
    ).?;
    make_variant(&raw_variant, @ptrCast(@constCast(&name)));

    var variant = godot.variant.Variant{ .value = raw_variant };
    defer variant.destroy();

    var text = variant.toString();
    defer godot.api.godot.destroy(godot.c.GDEXTENSION_VARIANT_TYPE_STRING, &text);

    const string_to_utf8 = godot.api.proc(
        godot.c.GDExtensionInterfaceStringToUtf8Chars,
        godot.api.godot.get_proc_address,
        "string_to_utf8_chars",
    );

    var buffer: [256]u8 = undefined;
    const full_length: usize = @intCast(string_to_utf8.?(&text, null, 0));
    const written = @min(full_length, buffer.len - 1);
    _ = string_to_utf8.?(&text, buffer[0..].ptr, @intCast(written));
    buffer[written] = 0;
    log(buffer[0..written :0].ptr);
}

pub fn v3subtract(a: Vector3, b: Vector3) Vector3 {
    return .{
        .x = a.x - b.x,
        .y = a.y - b.y,
        .z = a.z - b.z,
    };
}

pub fn v3cross(a: Vector3, b: Vector3) Vector3 {
    return .{
        .x = a.y * b.z - a.z * b.y,
        .y = a.z * b.x - a.x * b.z,
        .z = a.x * b.y - a.y * b.x,
    };
}

pub fn v3addTo(target: *Vector3, value: Vector3) void {
    target.x += value.x;
    target.y += value.y;
    target.z += value.z;
}

pub fn createArrayMesh() ArrayMesh {
    var class_name = godot.api.godot.stringName("ArrayMesh");
    defer godot.api.godot.destroy(
        godot.c.GDEXTENSION_VARIANT_TYPE_STRING_NAME,
        &class_name,
    );

    const object = godot.api.godot.classdb_construct_object.?(&class_name);

    return ArrayMesh.init(object);
}

pub fn createEmptyArray() godot.Array {
    var value: godot.types.Array = std.mem.zeroes(godot.types.Array);

    const constructor = godot.api.godot.variant_get_ptr_constructor.?(
        godot.c.GDEXTENSION_VARIANT_TYPE_ARRAY,
        0,
    ).?;

    constructor(&value, null);

    return .{ .value = value };
}

pub fn createEmtpyDictionary() godot.types.Dictionary {
    var value: godot.types.Dictionary = std.mem.zeroes(godot.types.Dictionary);

    const constructor = godot.api.godot.variant_get_ptr_constructor.?(
        godot.c.GDEXTENSION_VARIANT_TYPE_DICTIONARY,
        0,
    ).?;

    constructor(&value, null);

    return value;
}
