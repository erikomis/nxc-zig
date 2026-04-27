const std = @import("std");

pub const Modules = struct {
    lexer: *std.Build.Module,
    ast: *std.Build.Module,
    diagnostics: *std.Build.Module,
    parser: *std.Build.Module,
    paths: *std.Build.Module,
    decorators: *std.Build.Module,
    aliases: *std.Build.Module,
    class_names: *std.Build.Module,
    json5: *std.Build.Module,
    jsx: *std.Build.Module,
    module_interop: *std.Build.Module,
    modules: *std.Build.Module,
    pipeline: *std.Build.Module,
    declarations: *std.Build.Module,
    sourcemap: *std.Build.Module,
    codegen: *std.Build.Module,
    config: *std.Build.Module,
    cache: *std.Build.Module,
    compiler_core: *std.Build.Module,
    incremental: *std.Build.Module,
    compiler: *std.Build.Module,
};

pub const Package = struct {
    modules: Modules,
};

// Standalone: `zig build` from packages/compiler/
fn createModuleStandalone(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, rel: []const u8) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = b.path(rel),
        .target = target,
        .optimize = optimize,
    });
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lexer = createModuleStandalone(b, target, optimize, "src/syntax/lexer/lexer.zig");
    const ast = createModuleStandalone(b, target, optimize, "src/syntax/parser/ast.zig");
    ast.addImport("lexer", lexer);

    const diagnostics = b.addModule("diagnostics", .{
        .root_source_file = b.path("src/syntax/parser/diagnostics.zig"),
        .target = target,
        .optimize = optimize,
    });

    const parser = createModuleStandalone(b, target, optimize, "src/syntax/parser/parser.zig");
    parser.addImport("lexer", lexer);
    parser.addImport("ast", ast);
    parser.addImport("diagnostics", diagnostics);

    const paths = createModuleStandalone(b, target, optimize, "src/resolver/paths.zig");
    paths.addImport("parser", parser);

    const decorators = createModuleStandalone(b, target, optimize, "src/transform/decorators.zig");
    decorators.addImport("ast", ast);
    decorators.addImport("lexer", lexer);

    const aliases = createModuleStandalone(b, target, optimize, "src/resolver/aliases.zig");
    aliases.addImport("parser", parser);

    const class_names = createModuleStandalone(b, target, optimize, "src/transform/class_names.zig");
    class_names.addImport("ast", ast);

    const json5 = createModuleStandalone(b, target, optimize, "src/transform/json5.zig");

    const jsx = createModuleStandalone(b, target, optimize, "src/transform/jsx.zig");
    jsx.addImport("ast", ast);
    jsx.addImport("lexer", lexer);

    const module_interop = createModuleStandalone(b, target, optimize, "src/transform/module_interop.zig");
    module_interop.addImport("ast", ast);
    module_interop.addImport("lexer", lexer);
    module_interop.addImport("json5", json5);

    const modules = createModuleStandalone(b, target, optimize, "src/transform/modules.zig");
    modules.addImport("ast", ast);
    modules.addImport("lexer", lexer);
    modules.addImport("json5", json5);
    modules.addImport("module_interop", module_interop);

    const pipeline = createModuleStandalone(b, target, optimize, "src/transform/pipeline.zig");
    pipeline.addImport("parser", parser);
    pipeline.addImport("lexer", lexer);
    pipeline.addImport("paths", paths);
    pipeline.addImport("aliases", aliases);
    pipeline.addImport("ast", ast);
    pipeline.addImport("modules", modules);
    pipeline.addImport("decorators", decorators);
    pipeline.addImport("json5", json5);
    pipeline.addImport("jsx", jsx);

    const declarations = createModuleStandalone(b, target, optimize, "src/codegen/declarations.zig");
    declarations.addImport("ast", ast);

    const sourcemap = createModuleStandalone(b, target, optimize, "src/codegen/sourcemap.zig");

    const codegen = createModuleStandalone(b, target, optimize, "src/codegen/codegen.zig");
    codegen.addImport("lexer", lexer);
    codegen.addImport("parser", parser);
    codegen.addImport("ast", ast);
    codegen.addImport("sourcemap", sourcemap);

    const config = b.addModule("config", .{
        .root_source_file = b.path("src/core/config.zig"),
        .target = target,
        .optimize = optimize,
    });
    config.addImport("pipeline", pipeline);
    config.addImport("aliases", aliases);
    config.addImport("modules", modules);
    config.addImport("jsx", jsx);
    config.addImport("json5", json5);

    const cache = createModuleStandalone(b, target, optimize, "src/core/cache.zig");

    const compiler_core = createModuleStandalone(b, target, optimize, "src/core/compiler.zig");
    compiler_core.addImport("parser", parser);
    compiler_core.addImport("pipeline", pipeline);
    compiler_core.addImport("codegen", codegen);
    compiler_core.addImport("paths", paths);
    compiler_core.addImport("aliases", aliases);
    compiler_core.addImport("config", config);
    compiler_core.addImport("diagnostics", diagnostics);
    compiler_core.addImport("ast", ast);
    compiler_core.addImport("class_names", class_names);
    compiler_core.addImport("modules", modules);
    compiler_core.addImport("declarations", declarations);
    compiler_core.addImport("cache", cache);

    const incremental = b.addModule("incremental", .{
        .root_source_file = b.path("src/core/incremental.zig"),
        .target = target,
        .optimize = optimize,
    });
    incremental.addImport("cache", cache);
    incremental.addImport("compiler", compiler_core);
    incremental.addImport("config", config);
    incremental.addImport("diagnostics", diagnostics);

    compiler_core.addImport("incremental", incremental);

    const compiler = b.addModule("compiler", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    compiler.addImport("compiler_core", compiler_core);
    compiler.addImport("parser", parser);
    compiler.addImport("pipeline", pipeline);
    compiler.addImport("diagnostics", diagnostics);
    compiler.addImport("ast", ast);

    // N-API addons
    const parser_addon_mod = createModuleStandalone(b, target, optimize, "src/addons/parser.zig");
    parser_addon_mod.addImport("compiler", compiler);
    const parser_addon = b.addLibrary(.{ .linkage = .dynamic, .name = "parser", .root_module = parser_addon_mod });
    b.getInstallStep().dependOn(&b.addInstallArtifact(parser_addon, .{
        .dest_dir = .{ .override = .prefix },
        .dest_sub_path = "parser.node",
    }).step);

    const transform_addon_mod = createModuleStandalone(b, target, optimize, "src/addons/transform.zig");
    transform_addon_mod.addImport("compiler", compiler);
    const transform_addon = b.addLibrary(.{ .linkage = .dynamic, .name = "transform", .root_module = transform_addon_mod });
    b.getInstallStep().dependOn(&b.addInstallArtifact(transform_addon, .{
        .dest_dir = .{ .override = .prefix },
        .dest_sub_path = "transform.node",
    }).step);

    // Tests
    const test_mod = createModuleStandalone(b, target, optimize, "tests/compiler_test.zig");
    test_mod.addImport("compiler", compiler);
    const test_exe = b.addTest(.{ .root_module = test_mod });
    const test_step = b.step("test", "Run compiler tests");
    test_step.dependOn(&test_exe.step);
}

// Called from root build.zig with root-relative paths
pub fn addPackage(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) Package {
    const lexer = b.createModule(.{
        .root_source_file = b.path("packages/compiler/src/syntax/lexer/lexer.zig"),
        .target = target,
        .optimize = optimize,
    });

    const ast = b.createModule(.{
        .root_source_file = b.path("packages/compiler/src/syntax/parser/ast.zig"),
        .target = target,
        .optimize = optimize,
    });
    ast.addImport("lexer", lexer);

    const diagnostics = b.createModule(.{
        .root_source_file = b.path("packages/compiler/src/syntax/parser/diagnostics.zig"),
        .target = target,
        .optimize = optimize,
    });

    const parser = b.createModule(.{
        .root_source_file = b.path("packages/compiler/src/syntax/parser/parser.zig"),
        .target = target,
        .optimize = optimize,
    });
    parser.addImport("lexer", lexer);
    parser.addImport("ast", ast);
    parser.addImport("diagnostics", diagnostics);

    const paths = b.createModule(.{
        .root_source_file = b.path("packages/compiler/src/resolver/paths.zig"),
        .target = target,
        .optimize = optimize,
    });
    paths.addImport("parser", parser);

    const decorators = b.createModule(.{
        .root_source_file = b.path("packages/compiler/src/transform/decorators.zig"),
        .target = target,
        .optimize = optimize,
    });
    decorators.addImport("ast", ast);
    decorators.addImport("lexer", lexer);

    const aliases = b.createModule(.{
        .root_source_file = b.path("packages/compiler/src/resolver/aliases.zig"),
        .target = target,
        .optimize = optimize,
    });
    aliases.addImport("parser", parser);

    const class_names = b.createModule(.{
        .root_source_file = b.path("packages/compiler/src/transform/class_names.zig"),
        .target = target,
        .optimize = optimize,
    });
    class_names.addImport("ast", ast);

    const json5 = b.createModule(.{
        .root_source_file = b.path("packages/compiler/src/transform/json5.zig"),
        .target = target,
        .optimize = optimize,
    });

    const jsx = b.createModule(.{
        .root_source_file = b.path("packages/compiler/src/transform/jsx.zig"),
        .target = target,
        .optimize = optimize,
    });
    jsx.addImport("ast", ast);
    jsx.addImport("lexer", lexer);

    const module_interop = b.createModule(.{
        .root_source_file = b.path("packages/compiler/src/transform/module_interop.zig"),
        .target = target,
        .optimize = optimize,
    });
    module_interop.addImport("ast", ast);
    module_interop.addImport("lexer", lexer);
    module_interop.addImport("json5", json5);

    const modules = b.createModule(.{
        .root_source_file = b.path("packages/compiler/src/transform/modules.zig"),
        .target = target,
        .optimize = optimize,
    });
    modules.addImport("ast", ast);
    modules.addImport("lexer", lexer);
    modules.addImport("json5", json5);
    modules.addImport("module_interop", module_interop);

    const pipeline = b.createModule(.{
        .root_source_file = b.path("packages/compiler/src/transform/pipeline.zig"),
        .target = target,
        .optimize = optimize,
    });
    pipeline.addImport("parser", parser);
    pipeline.addImport("lexer", lexer);
    pipeline.addImport("paths", paths);
    pipeline.addImport("aliases", aliases);
    pipeline.addImport("ast", ast);
    pipeline.addImport("modules", modules);
    pipeline.addImport("decorators", decorators);
    pipeline.addImport("json5", json5);
    pipeline.addImport("jsx", jsx);

    const declarations = b.createModule(.{
        .root_source_file = b.path("packages/compiler/src/codegen/declarations.zig"),
        .target = target,
        .optimize = optimize,
    });
    declarations.addImport("ast", ast);

    const sourcemap = b.createModule(.{
        .root_source_file = b.path("packages/compiler/src/codegen/sourcemap.zig"),
        .target = target,
        .optimize = optimize,
    });

    const codegen = b.createModule(.{
        .root_source_file = b.path("packages/compiler/src/codegen/codegen.zig"),
        .target = target,
        .optimize = optimize,
    });
    codegen.addImport("lexer", lexer);
    codegen.addImport("parser", parser);
    codegen.addImport("ast", ast);
    codegen.addImport("sourcemap", sourcemap);

    const config = b.createModule(.{
        .root_source_file = b.path("packages/compiler/src/core/config.zig"),
        .target = target,
        .optimize = optimize,
    });
    config.addImport("pipeline", pipeline);
    config.addImport("aliases", aliases);
    config.addImport("modules", modules);
    config.addImport("jsx", jsx);
    config.addImport("json5", json5);

    const cache = b.createModule(.{
        .root_source_file = b.path("packages/compiler/src/core/cache.zig"),
        .target = target,
        .optimize = optimize,
    });

    const compiler_core = b.createModule(.{
        .root_source_file = b.path("packages/compiler/src/core/compiler.zig"),
        .target = target,
        .optimize = optimize,
    });
    compiler_core.addImport("parser", parser);
    compiler_core.addImport("pipeline", pipeline);
    compiler_core.addImport("codegen", codegen);
    compiler_core.addImport("paths", paths);
    compiler_core.addImport("aliases", aliases);
    compiler_core.addImport("config", config);
    compiler_core.addImport("diagnostics", diagnostics);
    compiler_core.addImport("ast", ast);
    compiler_core.addImport("class_names", class_names);
    compiler_core.addImport("modules", modules);
    compiler_core.addImport("declarations", declarations);
    compiler_core.addImport("cache", cache);

    const incremental = b.createModule(.{
        .root_source_file = b.path("packages/compiler/src/core/incremental.zig"),
        .target = target,
        .optimize = optimize,
    });
    incremental.addImport("cache", cache);
    incremental.addImport("compiler", compiler_core);
    incremental.addImport("config", config);
    incremental.addImport("diagnostics", diagnostics);

    compiler_core.addImport("incremental", incremental);

    const compiler = b.createModule(.{
        .root_source_file = b.path("packages/compiler/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    compiler.addImport("compiler_core", compiler_core);
    compiler.addImport("parser", parser);
    compiler.addImport("pipeline", pipeline);
    compiler.addImport("diagnostics", diagnostics);
    compiler.addImport("ast", ast);

    return .{
        .modules = .{
            .lexer = lexer,
            .ast = ast,
            .diagnostics = diagnostics,
            .parser = parser,
            .paths = paths,
            .decorators = decorators,
            .aliases = aliases,
            .class_names = class_names,
            .json5 = json5,
            .jsx = jsx,
            .module_interop = module_interop,
            .modules = modules,
            .pipeline = pipeline,
            .declarations = declarations,
            .sourcemap = sourcemap,
            .codegen = codegen,
            .config = config,
            .cache = cache,
            .compiler_core = compiler_core,
            .incremental = incremental,
            .compiler = compiler,
        },
    };
}

pub fn addParserAddon(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, compiler: *std.Build.Module) void {
    const addon_mod = b.createModule(.{
        .root_source_file = b.path("packages/compiler/src/addons/parser.zig"),
        .target = target,
        .optimize = optimize,
    });
    addon_mod.addImport("compiler", compiler);

    const addon = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "parser",
        .root_module = addon_mod,
    });
    b.getInstallStep().dependOn(&b.addInstallArtifact(addon, .{
        .dest_dir = .{ .override = .prefix },
        .dest_sub_path = "parser.node",
    }).step);
}

pub fn addTransformAddon(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, compiler: *std.Build.Module) void {
    const addon_mod = b.createModule(.{
        .root_source_file = b.path("packages/compiler/src/addons/transform.zig"),
        .target = target,
        .optimize = optimize,
    });
    addon_mod.addImport("compiler", compiler);

    const addon = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "transform",
        .root_module = addon_mod,
    });
    b.getInstallStep().dependOn(&b.addInstallArtifact(addon, .{
        .dest_dir = .{ .override = .prefix },
        .dest_sub_path = "transform.node",
    }).step);
}
