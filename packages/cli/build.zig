const std = @import("std");

pub const CompilerModules = struct {
    compiler: *std.Build.Module,
    config: *std.Build.Module,
    diagnostics: *std.Build.Module,
    incremental: *std.Build.Module,
};

pub const Package = struct {
    cli: *std.Build.Module,
    watch: *std.Build.Module,
};

// Standalone: `zig build` from packages/cli/
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const compiler_dep = b.dependency("compiler", .{ .target = target, .optimize = optimize });
    const linter_dep = b.dependency("linter", .{ .target = target, .optimize = optimize });
    const common_dep = b.dependency("common", .{ .target = target, .optimize = optimize });

    const compiler = compiler_dep.module("compiler");
    const diagnostics = compiler_dep.module("diagnostics");
    const incremental = compiler_dep.module("incremental");
    const linter = linter_dep.module("linter");
    const common = common_dep.module("common");

    // Build CLI modules with package-relative paths
    const old_cli = b.createModule(.{
        .root_source_file = b.path("src/legacy.zig"),
        .target = target,
        .optimize = optimize,
    });
    old_cli.addImport("compiler", compiler);
    old_cli.addImport("diagnostics", diagnostics);

    const watch = b.createModule(.{
        .root_source_file = b.path("src/watch.zig"),
        .target = target,
        .optimize = optimize,
    });
    watch.addImport("compiler", compiler);
    watch.addImport("incremental", incremental);
    watch.addImport("old_cli", old_cli);

    const cli = b.addModule("cli", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    cli.addImport("compiler", compiler);
    cli.addImport("linter", linter);
    cli.addImport("old_cli", old_cli);
    cli.addImport("common", common);
    cli.addImport("watch", watch);

    // Tests
    const test_mod = b.createModule(.{
        .root_source_file = b.path("tests/cli_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_mod.addImport("cli", cli);
    const test_exe = b.addTest(.{ .root_module = test_mod });
    const test_step = b.step("test", "Run CLI tests");
    test_step.dependOn(&test_exe.step);
}

// Called from root build.zig with root-relative paths
pub fn addPackage(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    compiler: CompilerModules,
    linter: *std.Build.Module,
    common: *std.Build.Module,
) Package {
    const old_cli = b.createModule(.{
        .root_source_file = b.path("packages/cli/src/legacy.zig"),
        .target = target,
        .optimize = optimize,
    });
    old_cli.addImport("compiler", compiler.compiler);
    old_cli.addImport("diagnostics", compiler.diagnostics);

    const watch = b.createModule(.{
        .root_source_file = b.path("packages/cli/src/watch.zig"),
        .target = target,
        .optimize = optimize,
    });
    watch.addImport("compiler", compiler.compiler);
    watch.addImport("incremental", compiler.incremental);
    watch.addImport("old_cli", old_cli);

    const cli = b.createModule(.{
        .root_source_file = b.path("packages/cli/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    cli.addImport("compiler", compiler.compiler);
    cli.addImport("linter", linter);
    cli.addImport("old_cli", old_cli);
    cli.addImport("common", common);
    cli.addImport("watch", watch);

    return .{ .cli = cli, .watch = watch };
}
