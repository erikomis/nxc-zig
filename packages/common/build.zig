const std = @import("std");

pub const Package = struct {
    module: *std.Build.Module,
};

// Standalone: `zig build` from packages/common/
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const module = b.addModule("common", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const test_mod = b.createModule(.{
        .root_source_file = b.path("tests/common_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_mod.addImport("common", module);

    const test_exe = b.addTest(.{ .root_module = test_mod });
    const test_step = b.step("test", "Run common tests");
    test_step.dependOn(&test_exe.step);
}

// Called from root build.zig with root-relative paths
pub fn addPackage(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) Package {
    const module = b.createModule(.{
        .root_source_file = b.path("packages/common/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    return .{ .module = module };
}
