const std = @import("std");

// Standalone: `zig build` from packages/formatter/
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const linter_dep = b.dependency("linter", .{ .target = target, .optimize = optimize });
    const linter = linter_dep.module("linter");

    const common_dep = b.dependency("common", .{ .target = target, .optimize = optimize });
    const common = common_dep.module("common");

    // N-API formatter addon
    const addon_mod = b.createModule(.{
        .root_source_file = b.path("src/addon.zig"),
        .target = target,
        .optimize = optimize,
    });
    addon_mod.addImport("linter", linter);
    addon_mod.addImport("common", common);

    const addon = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "formatter",
        .root_module = addon_mod,
    });
    b.getInstallStep().dependOn(&b.addInstallArtifact(addon, .{
        .dest_dir = .{ .override = .prefix },
        .dest_sub_path = "formatter.node",
    }).step);

    // Tests
    const test_mod = b.createModule(.{
        .root_source_file = b.path("tests/formatter.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_mod.addImport("linter", linter);
    test_mod.addImport("common", common);

    const test_exe = b.addTest(.{ .root_module = test_mod });
    const test_step = b.step("test", "Run formatter tests");
    test_step.dependOn(&test_exe.step);
}

// Called from root build.zig with root-relative paths
pub fn addFormatterAddon(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, linter: *std.Build.Module, common: *std.Build.Module) void {
    const addon_mod = b.createModule(.{
        .root_source_file = b.path("packages/formatter/src/addon.zig"),
        .target = target,
        .optimize = optimize,
    });
    addon_mod.addImport("linter", linter);
    addon_mod.addImport("common", common);

    const addon = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "formatter",
        .root_module = addon_mod,
    });
    b.getInstallStep().dependOn(&b.addInstallArtifact(addon, .{
        .dest_dir = .{ .override = .prefix },
        .dest_sub_path = "formatter.node",
    }).step);
}
