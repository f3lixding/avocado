const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const godot_zig = b.dependency("godot_zig", .{
        .target = target,
        .optimize = optimize,
    });

    const module = b.addModule("avocado", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "avocado",
        .root_module = module,
    });
    lib.root_module.addImport("godot_zig", godot_zig.module("godot_zig"));
}
