const std = @import("std");

const compiler = @import("compiler");
const config = @import("config");
const cli = @import("cli");
const linter = @import("linter");
const common = @import("common");
pub const ansi = @import("ansi.zig");
const terminal = @import("terminal.zig");

const Io = std.Io;

const usage =
    \\nxc - ESM-first TypeScript compiler written in Zig
    \\
    \\Usage:
    \\  nxc compile [options] <file|dir> [file|dir ...]
    \\  nxc lint <file> [file ...]
    \\  nxc format [--write] [--out-file <path>] <file>
    \\  nxc [options] <file|dir> [file|dir ...]
    \\
    \\Options:
    \\  --out-file <path>       Output file (single file only, default: stdout)
    \\  --out-dir  <dir>        Output directory (default: dist)
    \\  --delete-out-dir        Delete out-dir before compiling
    \\  --import-interop node|none     ESM interop strategy (default: node)
    \\  --jsx      classic|auto JSX runtime
    \\  --no-ts                 Disable TypeScript stripping
    \\  --config   <path>       Config file (default: tsconfig.json)
    \\  --watch                 Watch mode (poll-based)
    \\  -h, --help              Show help
    \\
    \\tsconfig.json keys:
    \\  compilerOptions.paths            Path aliases (e.g. {"#/*": ["./*"]})
    \\  compilerOptions.declaration      Emit .d.ts files when true
    \\
;

pub fn main(init: std.process.Init) !void {
    const alloc = init.gpa;
    const io = init.io;

    const args_slice = try init.minimal.args.toSlice(alloc);
    defer alloc.free(args_slice);

    if (args_slice.len > 1 and std.mem.eql(u8, args_slice[1], "lint")) {
        try runLintCommand(args_slice[2..], io, alloc);
        return;
    }

    if (args_slice.len > 1 and std.mem.eql(u8, args_slice[1], "format")) {
        try runFormatCommand(args_slice[2..], io, alloc);
        return;
    }

    var cfg = compiler.Config{};
    var input_paths = std.ArrayListUnmanaged([]const u8).empty;
    defer input_paths.deinit(alloc);
    var out_file: ?[]const u8 = null;
    var out_dir: ?[]const u8 = "dist";
    var config_path: []const u8 = "tsconfig.json";
    var watch = false;
    var delete_out_dir = false;
    var i: usize = if (args_slice.len > 1 and std.mem.eql(u8, args_slice[1], "compile")) 2 else 1;
    while (i < args_slice.len) : (i += 1) {
        const arg: []const u8 = args_slice[i];
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            try Io.File.stdout().writeStreamingAll(io, usage);
            return;
        } else if (std.mem.eql(u8, arg, "--out-file")) {
            i += 1;
            if (i >= args_slice.len) fatal("--out-file requires value");
            out_file = args_slice[i];
        } else if (std.mem.eql(u8, arg, "--out-dir")) {
            i += 1;
            if (i >= args_slice.len) fatal("--out-dir requires value");
            out_dir = args_slice[i];
        } else if (std.mem.eql(u8, arg, "--import-interop")) {
            i += 1;
            if (i >= args_slice.len) fatal("--import-interop requires value");
            if (std.mem.eql(u8, args_slice[i], "node")) {
                cfg.module.import_interop = .node;
            } else if (std.mem.eql(u8, args_slice[i], "none")) {
                cfg.module.import_interop = .none;
            } else fatal("--import-interop must be node or none");
        } else if (std.mem.eql(u8, arg, "--jsx")) {
            i += 1;
            if (i >= args_slice.len) fatal("--jsx requires value");
            cfg.jsx = true;
            cfg.transform.react.jsx_runtime = if (std.mem.eql(u8, args_slice[i], "auto") or std.mem.eql(u8, args_slice[i], "automatic"))
                .automatic
            else
                .classic;
        } else if (std.mem.eql(u8, arg, "--no-ts")) {
            cfg.parser.syntax = .ecmascript;
        } else if (std.mem.eql(u8, arg, "--config")) {
            i += 1;
            if (i >= args_slice.len) fatal("--config requires value");
            config_path = args_slice[i];
        } else if (std.mem.eql(u8, arg, "--watch")) {
            watch = true;
        } else if (std.mem.eql(u8, arg, "--delete-out-dir")) {
            delete_out_dir = true;
        } else if (arg.len > 0 and arg[0] != '-') {
            try input_paths.append(alloc, arg);
        } else {
            std.debug.print("unknown option: {s}\n", .{arg});
            std.process.exit(1);
        }
    }

    if (config.readTsConfig(config_path, io, alloc) catch null) |ts| {
        ts.compiler_options.applyTo(&cfg) catch |err| switch (err) {
            error.UnsupportedTsTarget => {
                const msg = "Unsupported tsconfig target. Only es2020, es2022, es2024, and esnext are allowed.";
                const colored = ansi.red(alloc, msg) catch {
                    std.debug.print("error: {s}\n", .{msg});
                    std.process.exit(1);
                };
                defer alloc.free(colored);
                std.debug.print("{s}\n", .{colored});
                std.process.exit(1);
            },
        };
    }

    if (input_paths.items.len == 0) {
        try Io.File.stdout().writeStreamingAll(io, usage);
        return;
    }

    if (input_paths.items.len > 1 and out_file != null) {
        fatal("--out-file can only be used with a single input");
    }

    if (delete_out_dir) {
        const od = out_dir orelse "dist";
        Io.Dir.cwd().deleteTree(io, od) catch |err| {
            std.debug.print("warning: failed to delete out dir: {}\n", .{err});
        };
    }

    if (watch) {
        try cli.watchAndCompile(input_paths.items, cfg, out_dir, out_file, io, alloc);
        return;
    }

    for (input_paths.items) |path| {
        switch (cli.classifyInputPath(path, io)) {
            .directory => {
                try cli.compileInput(path, null, out_dir orelse "dist", cfg, io, alloc);
            },
            .file => {
                cli.compileInput(path, out_file, out_dir, cfg, io, alloc) catch |err| {
                    printPathError("compile", path, err);
                    return err;
                };
            },
            .missing => {
                printPathError("compile", path, error.FileNotFound);
                return error.FileNotFound;
            },
        }
    }
}

fn runLintCommand(args: []const []const u8, io: Io, alloc: std.mem.Allocator) !void {
    if (args.len == 0) {
        try Io.File.stdout().writeStreamingAll(io, usage);
        return;
    }

    var fix = false;
    var verbose = false;
    var paths = std.ArrayListUnmanaged([]const u8).empty;
    defer paths.deinit(alloc);

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--fix")) {
            fix = true;
        } else if (std.mem.eql(u8, arg, "--verbose")) {
            verbose = true;
        } else if (arg.len > 0 and arg[0] != '-') {
            try paths.append(alloc, arg);
        } else {
            std.debug.print("unknown option: {s}\n", .{arg});
            std.process.exit(1);
        }
    }

    if (paths.items.len == 0) {
        try Io.File.stdout().writeStreamingAll(io, usage);
        return;
    }

    const start_ms = std.time.milliTimestamp();
    var had_errors = false;
    var fixed_count: usize = 0;
    var checked_count: usize = 0;
    for (paths.items) |path| {
        const file_start = std.time.milliTimestamp();

        const lint_result = try cli.lintPath(path, .{ .fix = fix }, io, alloc);
        defer lint_result.result.deinit(alloc);

        const elapsed_ms = std.time.milliTimestamp() - file_start;

        if (fix and lint_result.changed) {
            fixed_count += 1;
            if (verbose) std.debug.print("fixed {s} {d}ms\n", .{ path, elapsed_ms });
        } else {
            checked_count += 1;
            if (verbose) std.debug.print("checked {s} {d}ms\n", .{ path, elapsed_ms });

            for (lint_result.result.diagnostics) |diag| {
                printLintDiagnostic(diag);
                if (diag.severity == .err) had_errors = true;
            }
        }
    }

    const total_ms = std.time.milliTimestamp() - start_ms;
    if (fix) {
        if (fixed_count > 0) {
            std.debug.print("{d} file(s) formatted in {d}ms\n", .{ fixed_count, @as(u64, @intCast(total_ms)) });
        } else if (checked_count > 0) {
            std.debug.print("No files changed\n", .{});
        }
    }

    if (had_errors) return error.LintFailed;
}

fn runFormatCommand(args: []const []const u8, io: Io, alloc: std.mem.Allocator) !void {
    var write = false;
    var out_file: ?[]const u8 = null;
    var input: ?[]const u8 = null;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--write")) {
            write = true;
        } else if (std.mem.eql(u8, arg, "--out-file")) {
            i += 1;
            if (i >= args.len) fatal("--out-file requires value");
            out_file = args[i];
        } else if (arg.len > 0 and arg[0] != '-') {
            input = arg;
        } else {
            std.debug.print("unknown option: {s}\n", .{arg});
            std.process.exit(1);
        }
    }

    const path = input orelse {
        try Io.File.stdout().writeStreamingAll(io, usage);
        return;
    };
    const formatted = try cli.formatPath(path, .{ .out_file = out_file, .write = write, .options = common.FormatterOptions{} }, io, alloc);
    defer alloc.free(formatted);
    if (!write and out_file == null) try Io.File.stdout().writeStreamingAll(io, formatted);
}

fn printLintDiagnostic(diag: linter.Diagnostic) void {
    const sev = switch (diag.severity) {
        .err => "error",
        .warn => "warning",
        .info => "info",
    };
    std.debug.print("{s}:{d}:{d}: {s} {s}: {s}\n", .{
        diag.filename,
        diag.range.start.line,
        diag.range.start.column,
        sev,
        diag.rule_code,
        diag.message,
    });
}

pub fn applyTsConfigOverrides(cfg: *compiler.Config, ts: config.TsConfig) !void {
    try config.applyCompilerOptions(ts.compiler_options, @ptrCast(cfg));
}

test "applyTsConfigOverrides keeps esm-only module defaults" {
    var cfg = compiler.Config{};
    const defaults = compiler.Config{};
    const ts = config.TsConfig{};

    try applyTsConfigOverrides(&cfg, ts);

    try std.testing.expectEqual(defaults.module.target, cfg.module.target);
    try std.testing.expectEqual(defaults.module.import_interop, cfg.module.import_interop);
}

test "applyTsConfigOverrides preserves default module.strict when absent" {
    var cfg = compiler.Config{};
    const defaults = compiler.Config{};
    const ts = config.TsConfig{};

    try applyTsConfigOverrides(&cfg, ts);

    try std.testing.expectEqual(defaults.module.strict, cfg.module.strict);
}

test "applyTsConfigOverrides can disable module.strict explicitly" {
    var cfg = compiler.Config{};
    const ts = config.TsConfig{
        .compiler_options = .{ .strict = false },
    };

    try applyTsConfigOverrides(&cfg, ts);

    try std.testing.expectEqual(false, cfg.module.strict);
}

test "applyTsConfigOverrides can enable module.strict explicitly" {
    var cfg = compiler.Config{ .module = .{ .strict = false } };
    const ts = config.TsConfig{
        .compiler_options = .{ .strict = true },
    };

    try applyTsConfigOverrides(&cfg, ts);

    try std.testing.expectEqual(true, cfg.module.strict);
}

test "applyTsConfigOverrides preserves default decorators when experimentalDecorators is absent" {
    var cfg = compiler.Config{};
    const defaults = compiler.Config{};
    const ts = config.TsConfig{};

    try applyTsConfigOverrides(&cfg, ts);

    try std.testing.expectEqual(defaults.parser.decorators, cfg.parser.decorators);
}

test "applyTsConfigOverrides can disable decorators explicitly" {
    var cfg = compiler.Config{};
    const ts = config.TsConfig{
        .compiler_options = .{ .experimental_decorators = false },
    };

    try applyTsConfigOverrides(&cfg, ts);

    try std.testing.expectEqual(false, cfg.parser.decorators);
}

test "applyTsConfigOverrides can enable decorators explicitly" {
    var cfg = compiler.Config{ .parser = .{ .decorators = false } };
    const ts = config.TsConfig{
        .compiler_options = .{ .experimental_decorators = true },
    };

    try applyTsConfigOverrides(&cfg, ts);

    try std.testing.expectEqual(true, cfg.parser.decorators);
}

test "applyTsConfigOverrides maps target string" {
    var cfg = compiler.Config{};
    const ts = config.TsConfig{
        .compiler_options = .{ .target = "ES2020" },
    };
    try applyTsConfigOverrides(&cfg, ts);
    try std.testing.expectEqual(config.Target.es2020, cfg.target);
}

test "applyTsConfigOverrides maps target esnext" {
    var cfg = compiler.Config{};
    const ts = config.TsConfig{
        .compiler_options = .{ .target = "ESNext" },
    };
    try applyTsConfigOverrides(&cfg, ts);
    try std.testing.expectEqual(config.Target.esnext, cfg.target);
}

test "applyTsConfigOverrides rejects tsconfig target below es2020" {
    var cfg = compiler.Config{};
    const ts = config.TsConfig{
        .compiler_options = .{ .target = "ES2019" },
    };
    try std.testing.expectError(error.UnsupportedTsTarget, applyTsConfigOverrides(&cfg, ts));
}

test "applyTsConfigOverrides rejects unsupported tsconfig target" {
    var cfg = compiler.Config{};
    const ts = config.TsConfig{
        .compiler_options = .{ .target = "ES2018" },
    };
    try std.testing.expectError(error.UnsupportedTsTarget, applyTsConfigOverrides(&cfg, ts));
}

fn printPathError(action: []const u8, path: []const u8, err: anyerror) void {
    switch (err) {
        error.IsDir => std.debug.print("error: failed to {s} '{s}': expected a file path, but received a directory\n", .{ action, path }),
        error.FileNotFound => std.debug.print("error: failed to {s} '{s}': file not found\n", .{ action, path }),
        else => std.debug.print("error: failed to {s} '{s}': {}\n", .{ action, path, err }),
    }
}

fn fatal(msg: []const u8) noreturn {
    std.debug.print("error: {s}\n", .{msg});
    std.process.exit(1);
}
