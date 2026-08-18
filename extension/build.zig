const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const dev_build = b.option(bool, "dev-build", "used for zig build in dev shell");

    const godot_zig = b.dependency("godot_zig", .{
        .target = target,
        .optimize = optimize,
    });

    const lib_module = b.addModule("avocado", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "avocado",
        .root_module = lib_module,
    });
    lib.root_module.addImport("godot_zig", godot_zig.module("godot_zig"));

    if (dev_build) |d| {
        if (d) {
            const install = b.addInstallArtifact(lib, .{
                .dest_dir = .{ .override = .{ .custom = "../../bin" } },
            });

            b.getInstallStep().dependOn(&install.step);
        }
    }

    // just so the lsp works better
    const exe_module = b.addModule("exe", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_module.addImport("avocado", lib_module);
}
