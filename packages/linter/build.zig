const std = @import("std");

pub const Package = struct {
    module: *std.Build.Module,
};

// Standalone: `zig build` from packages/linter/
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const common_dep = b.dependency("common", .{ .target = target, .optimize = optimize });
    const common = common_dep.module("common");

    const module = b.addModule("linter", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    module.addImport("common", common);

    // N-API addon
    const addon_mod = b.createModule(.{
        .root_source_file = b.path("src/addon.zig"),
        .target = target,
        .optimize = optimize,
    });
    addon_mod.addImport("linter", module);
    addon_mod.addImport("common", common);

    const addon = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "lint",
        .root_module = addon_mod,
    });
    b.getInstallStep().dependOn(&b.addInstallArtifact(addon, .{
        .dest_dir = .{ .override = .prefix },
        .dest_sub_path = "lint.node",
    }).step);

    // Tests (package-relative paths)
    const test_mod = b.createModule(.{
        .root_source_file = b.path("tests/linter_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_mod.addImport("linter", module);
    test_mod.addImport("common", common);

    const test_exe = b.addTest(.{ .root_module = test_mod });
    const test_step = b.step("test", "Run linter tests");
    test_step.dependOn(&test_exe.step);
}

// Called from root build.zig with root-relative paths
pub fn addPackage(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, common: *std.Build.Module) Package {
    const module = b.createModule(.{
        .root_source_file = b.path("packages/linter/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    module.addImport("common", common);
    return .{ .module = module };
}

pub fn addLintAddon(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, linter: *std.Build.Module, common: *std.Build.Module) void {
    const addon_mod = b.createModule(.{
        .root_source_file = b.path("packages/linter/src/addon.zig"),
        .target = target,
        .optimize = optimize,
    });
    addon_mod.addImport("linter", linter);
    addon_mod.addImport("common", common);

    const addon = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "lint",
        .root_module = addon_mod,
    });
    b.getInstallStep().dependOn(&b.addInstallArtifact(addon, .{
        .dest_dir = .{ .override = .prefix },
        .dest_sub_path = "lint.node",
    }).step);
}
