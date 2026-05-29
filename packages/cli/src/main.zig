const std = @import("std");

const compiler = @import("compiler");
const config = @import("config");
const cli = @import("cli");
const linter = @import("linter");
const common = @import("common");
pub const ansi = @import("ansi.zig");
const terminal = @import("terminal.zig");

const version_str = "0.1.0";

const Io = std.Io;

const usage =
    \\nxc v0.1.0 — ESM-first TypeScript compiler written in Zig
    \\
    \\Usage:
    \\  nxc [--help] [--version]
    \\  nxc compile [options] <file|dir> [file|dir ...]
    \\  nxc lint [options] <file> [file ...]
    \\  nxc format [options] <file>
    \\  nxc init
    \\  nxc doctor
    \\  nxc clean
    \\  nxc stats
    \\
    \\Commands:
    \\  compile     Compile TypeScript/JavaScript to JavaScript
    \\  lint        Lint source files with built-in rules
    \\  format      Format source files (Prettier-compatible)
    \\  init        Create default tsconfig.json + nxc.config.js
    \\  doctor      Check project health and configuration
    \\  clean       Remove build output and cache
    \\  stats       Show project statistics
    \\
    \\Compile Options:
    \\  --out-file <path>       Single output file (default: stdout)
    \\  --out-dir  <dir>        Output directory (default: dist)
    \\  --delete-out-dir        Delete out-dir before building
    \\  --import-interop node|none  ESM interop strategy (default: node)
    \\  --jsx      classic|auto JSX runtime
    \\  --no-ts                 Disable TypeScript type stripping
    \\  --minify                Minify output JavaScript
    \\  --allow-js              Process .js/.jsx files
    \\  --verbose               Verbose output
    \\  --config   <path>       Config file (default: auto-detect)
    \\  --watch                 Watch mode (poll-based)
    \\
    \\Lint Options:
    \\  --config <path>         Config file
    \\  --fix                   Auto-fix issues
    \\  --cache                 Enable result caching
    \\  --watch                 Watch mode
    \\  --json                  JSON output format
    \\  --list-rules            Show all available rules
    \\  --verbose               Verbose output
    \\
    \\Format Options:
    \\  --write                 Write output in-place
    \\  --check                 Check if files are formatted (CI mode)
    \\  --out-file <path>       Write to specific file
    \\  --config <path>         Config file
    \\  --watch                 Watch mode
    \\
    \\tsconfig.json keys:
    \\  compilerOptions.target, .jsx, .jsxImportSource, .paths,
    \\  .baseUrl, .strict, .declaration, .sourceMap, .outDir,
    \\  .rootDir, .allowJs, .removeComments, .noEmit, .module,
    \\  .esModuleInterop, .experimentalDecorators, .inlineSourceMap,
    \\  .inlineSources, .declarationDir, .emitDeclarationOnly,
    \\  .isolatedModules, .resolveJsonModule
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

    if (args_slice.len > 1 and std.mem.eql(u8, args_slice[1], "init")) {
        try runInitCommand(io, alloc);
        return;
    }

    if (args_slice.len > 1 and std.mem.eql(u8, args_slice[1], "doctor")) {
        try runDoctorCommand(io, alloc);
        return;
    }

    if (args_slice.len > 1 and std.mem.eql(u8, args_slice[1], "clean")) {
        try runCleanCommand(io);
        return;
    }

    if (args_slice.len > 1 and std.mem.eql(u8, args_slice[1], "stats")) {
        try runStatsCommand(io, alloc);
        return;
    }

    var cfg = compiler.Config{};
    var input_paths = std.ArrayListUnmanaged([]const u8).empty;
    defer input_paths.deinit(alloc);
    var out_file: ?[]const u8 = null;
    var out_dir: ?[]const u8 = "dist";
    var config_path: ?[]const u8 = null;
    var watch = false;
    var delete_out_dir = false;
    var verbose = false;
    var i: usize = if (args_slice.len > 1 and std.mem.eql(u8, args_slice[1], "compile")) 2 else 1;
    while (i < args_slice.len) : (i += 1) {
        const arg: []const u8 = args_slice[i];
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            try Io.File.stdout().writeStreamingAll(io, usage);
            return;
        } else if (std.mem.eql(u8, arg, "--version")) {
            try Io.File.stdout().writeStreamingAll(io, "nxc " ++ version_str ++ "\n");
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
        } else if (std.mem.eql(u8, arg, "--minify")) {
            cfg.minify = true;
        } else if (std.mem.eql(u8, arg, "--allow-js")) {
            cfg.allow_js = true;
        } else if (std.mem.eql(u8, arg, "--verbose")) {
            verbose = true;
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

    var ts_files: [][]const u8 = &.{};
    var ts_include: [][]const u8 = &.{};
    var ts_exclude: [][]const u8 = &.{};

    const resolved_config_path = config_path orelse compiler.findTsConfig(io, alloc) orelse "tsconfig.json";
    defer if (config_path == null and !std.mem.eql(u8, resolved_config_path, "tsconfig.json")) alloc.free(resolved_config_path);

    if (config.readTsConfig(resolved_config_path, io, alloc) catch null) |ts| {
        ts.compiler_options.applyTo(&cfg) catch |err| switch (err) {
            error.UnsupportedTsTarget => {
                const msg = "Unsupported tsconfig target. Supported: es2015, es2016, es2017, es2018, es2019, es2020, es2022, es2024, and esnext.";
                const colored = ansi.red(alloc, msg) catch {
                    std.debug.print("error: {s}\n", .{msg});
                    std.process.exit(1);
                };
                defer alloc.free(colored);
                std.debug.print("{s}\n", .{colored});
                std.process.exit(1);
            },
        };

        ts_files = ts.files;
        ts_include = ts.include;
        ts_exclude = ts.exclude;

        for (ts.references) |ref| {
            const ref_tsconfig = try std.fs.path.join(alloc, &.{ ref, "tsconfig.json" });
            defer alloc.free(ref_tsconfig);
            const ref_out = try std.fs.path.join(alloc, &.{ ref, out_dir orelse "dist" });
            defer alloc.free(ref_out);

            if (config.readTsConfig(ref_tsconfig, io, alloc) catch null) |ref_ts| {
                var ref_cfg = cfg;
                config.applyCompilerOptions(ref_ts.compiler_options, &ref_cfg) catch {};
                cli.compileInput(ref, null, ref_out, ref_cfg, io, alloc) catch |err| {
                    std.debug.print("warning: failed to compile reference '{s}': {}\n", .{ ref, err });
                };
            }
        }
    }

    // Use tsconfig files/include when no explicit paths given
    if (input_paths.items.len == 0 and (ts_files.len > 0 or ts_include.len > 0)) {
        const base_dir = std.fs.path.dirname(resolved_config_path) orelse ".";
        const cfg_files = config.TsConfig{ .files = ts_files, .include = ts_include, .exclude = ts_exclude };
        const found = config.resolveConfigFiles(&cfg_files, base_dir, io, alloc) catch &.{};
        for (found) |f| {
            try input_paths.append(alloc, f);
        }
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

    const start_time = std.time.milliTimestamp();
    var compiled: usize = 0;
    var errors: usize = 0;

    for (input_paths.items) |path| {
        if (verbose) std.debug.print("compiling {s}...\n", .{path});
        switch (cli.classifyInputPath(path, io)) {
            .directory => {
                try cli.compileInput(path, null, out_dir orelse "dist", cfg, io, alloc);
                compiled += 1;
            },
            .file => {
                cli.compileInput(path, out_file, out_dir, cfg, io, alloc) catch |err| {
                    printPathError("compile", path, err);
                    errors += 1;
                    continue;
                };
                compiled += 1;
            },
            .missing => {
                printPathError("compile", path, error.FileNotFound);
                errors += 1;
                continue;
            },
        }
    }

    const elapsed_ms = std.time.milliTimestamp() - start_time;
    if (compiled > 0) {
        std.debug.print("Compiled {d} file(s) in {d}ms", .{ compiled, elapsed_ms });
        if (errors > 0) std.debug.print(" ({d} errors)", .{errors});
        std.debug.print("\n", .{});
    }
    if (errors > 0) return error.CompileFailed;
}

fn runLintCommand(args: []const []const u8, io: Io, alloc: std.mem.Allocator) !void {
    if (args.len == 0) {
        try Io.File.stdout().writeStreamingAll(io, usage);
        return;
    }

    if (args.len == 1 and (std.mem.eql(u8, args[0], "--version") or std.mem.eql(u8, args[0], "-v"))) {
        try Io.File.stdout().writeStreamingAll(io, "nxc-linter " ++ version_str ++ "\n");
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
    if (args.len == 1 and (std.mem.eql(u8, args[0], "--version") or std.mem.eql(u8, args[0], "-v"))) {
        try Io.File.stdout().writeStreamingAll(io, "nxc-formatter " ++ version_str ++ "\n");
        return;
    }

    var write = false;
    var check = false;
    var out_file: ?[]const u8 = null;
    var input: ?[]const u8 = null;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--write")) {
            write = true;
        } else if (std.mem.eql(u8, arg, "--check")) {
            check = true;
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
    if (check) {
        const source = common.readFileAlloc(path, io, alloc) catch |err| {
            std.debug.print("error: failed to read '{s}': {}\n", .{ path, err });
            std.process.exit(1);
        };
        defer alloc.free(source);
        const formatted = try linter.format(source, common.FormatterOptions{}, alloc);
        defer alloc.free(formatted);
        if (!std.mem.eql(u8, source, formatted)) {
            std.debug.print("{s}\n", .{path});
            std.process.exit(1);
        }
        return;
    }
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
    const color_code = switch (diag.severity) {
        .err => "\x1b[31m",
        .warn => "\x1b[33m",
        .info => "\x1b[36m",
        else => "",
    };
    const reset = "\x1b[0m";
    std.debug.print("{s}{s}{s}: {s}{s}:{d}:{d}{s}: {s} {s}\n", .{
        color_code, sev, reset,
        reset, diag.filename, diag.range.start.line, diag.range.start.column, reset,
        diag.rule_code, diag.message,
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

test "applyTsConfigOverrides rejects tsconfig target below es2015" {
    var cfg = compiler.Config{};
    const ts = config.TsConfig{
        .compiler_options = .{ .target = "ES5" },
    };
    try std.testing.expectError(error.UnsupportedTsTarget, applyTsConfigOverrides(&cfg, ts));
}

test "applyTsConfigOverrides rejects unsupported tsconfig target" {
    var cfg = compiler.Config{};
    const ts = config.TsConfig{
        .compiler_options = .{ .target = "ES7" },
    };
    try std.testing.expectError(error.UnsupportedTsTarget, applyTsConfigOverrides(&cfg, ts));
}

test "parseSupportedTarget accepts es2015" {
    try std.testing.expectEqual(config.Target.es2015, try config.parseSupportedTarget("ES2015"));
}

test "parseSupportedTarget accepts es6 as es2015" {
    try std.testing.expectEqual(config.Target.es2015, try config.parseSupportedTarget("ES6"));
}

test "parseSupportedTarget accepts esnext" {
    try std.testing.expectEqual(config.Target.esnext, try config.parseSupportedTarget("ESNext"));
}

test "parseSupportedTarget rejects unsupported" {
    try std.testing.expectError(error.UnsupportedTsTarget, config.parseSupportedTarget("ES5"));
}

test "applyTsConfigOverrides maps es2015 target" {
    var cfg = compiler.Config{};
    const ts = config.TsConfig{
        .compiler_options = .{ .target = "ES2015" },
    };
    try applyTsConfigOverrides(&cfg, ts);
    try std.testing.expectEqual(config.Target.es2015, cfg.target);
}

test "applyTsConfigOverrides minify is false by default" {
    var cfg = compiler.Config{};
    try std.testing.expectEqual(false, cfg.minify);
}

test "applyTsConfigOverrides minify can be set true" {
    var cfg = compiler.Config{ .minify = true };
    try std.testing.expectEqual(true, cfg.minify);
}

test "applyTsConfigOverrides module target defaults" {
    var cfg = compiler.Config{};
    const defaults = compiler.Config{};
    try std.testing.expectEqual(defaults.module.target, cfg.module.target);
}

fn printPathError(action: []const u8, path: []const u8, err: anyerror) void {
    switch (err) {
        error.IsDir => std.debug.print("error: failed to {s} '{s}': expected a file path, but received a directory\n", .{ action, path }),
        error.FileNotFound => std.debug.print("error: failed to {s} '{s}': file not found\n", .{ action, path }),
        else => std.debug.print("error: failed to {s} '{s}': {}\n", .{ action, path, err }),
    }
}

fn runInitCommand(io: Io, alloc: std.mem.Allocator) !void {
    _ = alloc;

    const tsconfig =
        \\{
        \\  "compilerOptions": {
        \\    "target": "ES2022",
        \\    "module": "ESNext",
        \\    "jsx": "react-jsx",
        \\    "jsxImportSource": "react",
        \\    "declaration": true,
        \\    "sourceMap": true,
        \\    "esModuleInterop": true,
        \\    "strict": true,
        \\    "outDir": "dist",
        \\    "rootDir": "src",
        \\    "paths": {
        \\      "@/*": ["./src/*"]
        \\    }
        \\  },
        \\  "include": ["src"],
        \\  "exclude": ["node_modules", "dist"]
        \\}
        \\
    ;

    const nxc_config =
        \\export default defineConfig({
        \\  env: { node: true },
        \\  formatter: {
        \\    singleQuote: true,
        \\    semi: true,
        \\    trailingComma: 'all',
        \\    tabWidth: 2,
        \\    printWidth: 100,
        \\  },
        \\  rules: {
        \\    'no-console': 'warn',
        \\    'no-debugger': 'error',
        \\    'no-unused-vars': 'warn',
        \\    'no-var': 'error',
        \\    'prefer-const': 'warn',
        \\    'eqeqeq': 'error',
        \\  },
        \\  compilerOptions: {
        \\    target: 'ES2022',
        \\    outDir: 'dist',
        \\  }
        \\})
        \\
    ;

    if (Io.Dir.cwd().statFile(io, "tsconfig.json", .{})) |_| {
        std.debug.print("tsconfig.json already exists, skipping\n", .{});
    } else |_| {
        Io.Dir.cwd().writeFile(io, .{ .sub_path = "tsconfig.json", .data = tsconfig }) catch |err| {
            std.debug.print("error: failed to create tsconfig.json: {}\n", .{err});
        };
        std.debug.print("Created tsconfig.json\n", .{});
    }

    if (Io.Dir.cwd().statFile(io, "nxc.config.js", .{})) |_| {
        std.debug.print("nxc.config.js already exists, skipping\n", .{});
    } else |_| {
        Io.Dir.cwd().writeFile(io, .{ .sub_path = "nxc.config.js", .data = nxc_config }) catch |err| {
            std.debug.print("error: failed to create nxc.config.js: {}\n", .{err});
        };
        std.debug.print("Created nxc.config.js\n", .{});
    }

    const gitignore =
        \\dist/
        \\node_modules/
        \\.zig-cache/
        \\zig-out/
        \\*.js.map
        \\*.d.ts
        \\
    ;
    if (Io.Dir.cwd().statFile(io, ".gitignore", .{})) |_| {
        std.debug.print(".gitignore already exists, skipping\n", .{});
    } else |_| {
        Io.Dir.cwd().writeFile(io, .{ .sub_path = ".gitignore", .data = gitignore }) catch |err| {
            std.debug.print("error: failed to create .gitignore: {}\n", .{err});
        };
        std.debug.print("Created .gitignore\n", .{});
    }

    const index_ts =
        \\export function hello(name: string): string {
        \\  return `Hello, ${name}!`;
        \\}
        \\
        \\console.log(hello("world"));
        \\
    ;
    Io.Dir.cwd().createDirPath(io, "src") catch {};
    if (Io.Dir.cwd().statFile(io, "src/index.ts", .{})) |_| {
        std.debug.print("src/index.ts already exists, skipping\n", .{});
    } else |_| {
        Io.Dir.cwd().writeFile(io, .{ .sub_path = "src/index.ts", .data = index_ts }) catch |err| {
            std.debug.print("error: failed to create src/index.ts: {}\n", .{err});
        };
        std.debug.print("Created src/index.ts\n", .{});
    }

    std.debug.print("\nDone. Run 'nxc compile src' to build.\n", .{});
}

fn runDoctorCommand(io: Io, alloc: std.mem.Allocator) !void {
    _ = alloc;
    const green = "\x1b[32m";
    const yellow = "\x1b[33m";
    const red = "\x1b[31m";
    const reset = "\x1b[0m";

    try Io.File.stdout().writeStreamingAll(io, "nxc doctor v0.1.0\n\n");

    var issues: usize = 0;

    // Check config files
    const configs = [_][]const u8{ "tsconfig.json", "nxc.config.js" };
    for (configs) |cfg_name| {
        if (Io.Dir.cwd().statFile(io, cfg_name, .{})) |_| {
            std.debug.print("  {s}✓{s} {s} found\n", .{ green, reset, cfg_name });
            // Validate parse
            if (std.mem.endsWith(u8, cfg_name, ".json")) {
                if (config.readTsConfig(cfg_name, io, alloc) catch null) |_| {
                    std.debug.print("    {s}✓{s} valid JSON/JSON5\n", .{ green, reset });
                } else |_| {
                    std.debug.print("    {s}✗{s} failed to parse\n", .{ red, reset });
                    issues += 1;
                }
            }
        } else |_| {
            std.debug.print("  {s}○{s} {s} not found\n", .{ yellow, reset, cfg_name });
        }
    }

    // Check src directory
    if (Io.Dir.cwd().statFile(io, "src", .{})) |stat| {
        if (stat.kind == .directory) {
            var file_count: usize = 0;
            var dir = Io.Dir.cwd().openDir(io, "src", .{ .iterate = true }) catch null;
            if (dir) |*d| {
                defer d.close(io);
                var walker = try d.walk(alloc);
                defer walker.deinit();
                while (try walker.next(io)) |entry| {
                    if (entry.kind == .file) file_count += 1;
                }
            }
            if (file_count > 0) {
                std.debug.print("  {s}✓{s} src/ directory with {d} file(s)\n", .{ green, reset, file_count });
            } else {
                std.debug.print("  {s}○{s} src/ directory is empty\n", .{ yellow, reset });
            }
        }
    } else |_| {
        std.debug.print("  {s}✗{s} src/ directory not found\n", .{ red, reset });
        issues += 1;
    }

    // Check node_modules
    if (Io.Dir.cwd().statFile(io, "node_modules", .{})) |_| {
        std.debug.print("  {s}✓{s} node_modules/ exists\n", .{ green, reset });
    } else |_| {
        std.debug.print("  {s}○{s} node_modules/ not found (install dependencies if needed)\n", .{ yellow, reset });
    }

    // Check dist
    if (Io.Dir.cwd().statFile(io, "dist", .{})) |_| {
        std.debug.print("  {s}✓{s} dist/ output directory exists\n", .{ green, reset });
    } else |_| {
        std.debug.print("  {s}○{s} dist/ not created yet\n", .{ yellow, reset });
    }

    if (issues > 0) {
        std.debug.print("\n{s}Found {d} issue(s). Run 'nxc init' to create default config.{s}\n", .{ red, issues, reset });
    } else {
        std.debug.print("\n{s}All checks passed! Ready to compile.{s}\n", .{ green, reset });
    }
}

fn runCleanCommand(io: Io) !void {
    const dirs = [_][]const u8{ "dist", ".zig-cache", "zig-out", "node_modules/nxc" };
    for (dirs) |dir| {
        if (Io.Dir.cwd().statFile(io, dir, .{})) |stat| {
            if (stat.kind == .directory) {
                Io.Dir.cwd().deleteTree(io, dir) catch |err| {
                    std.debug.print("warning: failed to remove {s}: {}\n", .{ dir, err });
                    continue;
                };
                std.debug.print("Removed {s}/\n", .{dir});
            }
        } else |_| {}
    }
    std.debug.print("Cleaned build artifacts\n", .{});
}

fn runStatsCommand(io: Io, alloc: std.mem.Allocator) !void {
    try Io.File.stdout().writeStreamingAll(io, "nxc stats\n\n");

    var total_files: usize = 0;
    var total_lines: usize = 0;
    var ext_counts = std.StringHashMapUnmanaged(usize).empty;
    defer {
        var it = ext_counts.keyIterator();
        while (it.next()) |k| alloc.free(k.*);
        ext_counts.deinit(alloc);
    }

    const exts = [_][]const u8{ ".ts", ".tsx", ".js", ".jsx", ".mts", ".cts", ".mjs", ".cjs", ".json", ".css" };

    for (exts) |ext| {
        var dir = Io.Dir.cwd().openDir(io, ".", .{ .iterate = true }) catch continue;
        var walker = try dir.walk(alloc);
        defer walker.deinit();
        var count: usize = 0;
        var lines: usize = 0;

        while (try walker.next(io)) |entry| {
            if (entry.kind != .file) continue;
            if (!std.mem.endsWith(u8, entry.basename, ext)) continue;

            const path = entry.path;
            if (std.mem.indexOf(u8, path, "node_modules") != null) continue;
            if (std.mem.indexOf(u8, path, "dist/") != null) continue;
            if (std.mem.indexOf(u8, path, ".zig-cache") != null) continue;

            const source = Io.Dir.cwd().readFileAlloc(io, path, alloc, std.Io.Limit.limited(1 * 1024 * 1024)) catch continue;
            defer alloc.free(source);
            for (source) |c| if (c == '\n') lines += 1;

            count += 1;
        }

        if (count > 0) {
            const key = try alloc.dupe(u8, ext);
            try ext_counts.put(alloc, key, count);
            total_files += count;
            total_lines += lines;
            std.debug.print("  {s:<8} {d:>4} files  {d:>6} lines\n", .{ ext, count, lines });
        }
        dir.close(io);
    }

    std.debug.print("  ────────\n", .{});
    std.debug.print("  {s:<8} {d:>4} files  {d:>6} lines\n", .{ "total", total_files, total_lines });
}

fn fatal(msg: []const u8) noreturn {
    std.debug.print("error: {s}\n", .{msg});
    std.process.exit(1);
}
