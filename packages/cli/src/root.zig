const std = @import("std");

const compiler = @import("compiler");
const linter = @import("linter");
const old_cli = @import("old_cli");
const common = @import("common");
const watch = @import("watch");

pub const InputKind = old_cli.InputKind;
pub const isTranspilable = old_cli.isTranspilable;
pub const isCopyableJs = old_cli.isCopyableJs;
pub const isCompilable = old_cli.isCompilable;
pub const isDefaultIgnored = old_cli.isDefaultIgnored;
pub const buildOutPath = old_cli.buildOutPath;
pub const buildCopyOutPath = old_cli.buildCopyOutPath;
pub const buildMapPath = old_cli.buildMapPath;
pub const appendSourceMapComment = old_cli.appendSourceMapComment;
pub const classifyInputPath = old_cli.classifyInputPath;
pub const compileInput = old_cli.compileInput;
pub const collectFiles = old_cli.collectFiles;
pub const compileDirAll = old_cli.compileDirAll;
pub const copySingle = old_cli.copySingle;
pub const compileSingle = old_cli.compileSingle;
pub const watchAndCompile = watch.watchAndCompile;

pub const Command = enum { compile, lint, format };

pub const CompileOptions = struct {
    out_file: ?[]const u8 = null,
    out_dir: ?[]const u8 = "dist",
    config: compiler.Config = .{},
};

pub const LintOptions = struct {
    fix: bool = false,
    registry: ?linter.Registry = null,
    plugins: []const common.Plugin = &.{},
    config: ?linter.Config = null,
    config_path: ?[]const u8 = null,
};

pub const FormatOptions = struct {
    out_file: ?[]const u8 = null,
    write: bool = false,
    options: common.FormatterOptions = .{},
};

pub fn compilePath(path: []const u8, options: CompileOptions, io: std.Io, alloc: std.mem.Allocator) !void {
    try old_cli.compileInput(path, options.out_file, options.out_dir, options.config, io, alloc);
}

pub fn lintPath(path: []const u8, options: LintOptions, io: std.Io, alloc: std.mem.Allocator) !struct { result: linter.Result, changed: bool } {
    const source = try common.readFileAlloc(path, io, alloc);
    defer alloc.free(source);
    const owned_cfg = options.config == null;
    var cfg = options.config orelse readLinterConfig(options.config_path, io, alloc);
    if (!owned_cfg) {
    }
    const result = try if (options.registry) |registry|
        linter.lintAndFormat(source, path, registry, cfg, alloc)
    else if (options.plugins.len > 0)
        linter.lintWithPluginsAndConfig(source, path, options.plugins, cfg, alloc)
    else
        linter.lintWithConfig(source, path, cfg, alloc);
    if (owned_cfg) cfg.deinit(alloc);

    if (options.fix) {
        const to_write = result.formatted orelse result.fixed_source;
        if (to_write) |data| {
            const changed = !std.mem.eql(u8, source, data);
            if (changed) {
                try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = data });
            }
            return .{ .result = result, .changed = changed };
        }
    }

    return .{ .result = result, .changed = false };
}

fn readLinterConfig(config_path: ?[]const u8, io: std.Io, alloc: std.mem.Allocator) linter.Config {
    if (config_path) |path| {
        return linter.readConfigFile(path, io, alloc) catch .{};
    }

    return linter.searchConfigCwd(io, alloc);
}

pub fn formatPath(path: []const u8, options: FormatOptions, io: std.Io, alloc: std.mem.Allocator) ![]u8 {
    const source = try common.readFileAlloc(path, io, alloc);
    defer alloc.free(source);
    const formatted = try linter.format(source, options.options, alloc);
    errdefer alloc.free(formatted);

    if (options.write) {
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = options.out_file orelse path, .data = formatted });
    } else if (options.out_file) |out_file| {
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = out_file, .data = formatted });
    }

    return formatted;
}
