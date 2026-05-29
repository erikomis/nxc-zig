const std = @import("std");

const cli = @import("cli");
const compiler = @import("compiler");
const config = @import("config");

const usage =
    \\nxc-compiler - compile TypeScript/JavaScript
    \\
    \\Usage:
    \\  nxc-compiler [options] <file|dir> [file|dir ...]
    \\
    \\Options:
    \\  --out-file <path>       Output file (single file only, default: stdout)
    \\  --out-dir  <dir>        Output directory (default: dist)
    \\  --delete-out-dir        Delete out-dir before compiling
    \\  --import-interop node|none
    \\  --jsx      classic|auto JSX runtime
    \\  --no-ts                 Disable TypeScript stripping
    \\  --minify                Minify output
    \\  --allow-js              Allow JavaScript files
    \\  --verbose               Verbose output
    \\  --profile               Show per-file compile times
    \\  --bail                  Stop on first error
    \\  --config   <path>       Config file (default: tsconfig.json)
    \\  -h, --help              Show help
    \\  --version               Show version
    \\
;

pub fn main(init: std.process.Init) !void {
    const alloc = init.gpa;
    const io = init.io;
    const args = try init.minimal.args.toSlice(alloc);
    defer alloc.free(args);

    var cfg: config.Config = .{};
    var input_paths = std.ArrayListUnmanaged([]const u8).empty;
    defer input_paths.deinit(alloc);
    var out_file: ?[]const u8 = null;
    var out_dir: ?[]const u8 = "dist";
    var config_path: ?[]const u8 = null;
    var delete_out_dir = false;
    var verbose = false;
    var profile = false;
    var bail_on_error = false;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            try std.Io.File.stdout().writeStreamingAll(io, usage);
            return;
        } else if (std.mem.eql(u8, arg, "--version")) {
            try std.Io.File.stdout().writeStreamingAll(io, "nxc-compiler 0.1.0\n");
            return;
        } else if (std.mem.eql(u8, arg, "--out-file")) {
            i += 1;
            if (i >= args.len) fatal("--out-file requires value");
            out_file = args[i];
        } else if (std.mem.eql(u8, arg, "--out-dir")) {
            i += 1;
            if (i >= args.len) fatal("--out-dir requires value");
            out_dir = args[i];
        } else if (std.mem.eql(u8, arg, "--import-interop")) {
            i += 1;
            if (i >= args.len) fatal("--import-interop requires value");
            if (std.mem.eql(u8, args[i], "node")) cfg.module.import_interop = .node else if (std.mem.eql(u8, args[i], "none")) cfg.module.import_interop = .none else fatal("--import-interop must be node or none");
        } else if (std.mem.eql(u8, arg, "--jsx")) {
            i += 1;
            if (i >= args.len) fatal("--jsx requires value");
            cfg.jsx = true;
            cfg.transform.react.jsx_runtime = if (std.mem.eql(u8, args[i], "auto") or std.mem.eql(u8, args[i], "automatic")) .automatic else .classic;
        } else if (std.mem.eql(u8, arg, "--no-ts")) {
            cfg.parser.syntax = .ecmascript;
        } else if (std.mem.eql(u8, arg, "--minify")) {
            cfg.minify = true;
        } else if (std.mem.eql(u8, arg, "--allow-js")) {
            cfg.allow_js = true;
        } else if (std.mem.eql(u8, arg, "--verbose")) {
            verbose = true;
        } else if (std.mem.eql(u8, arg, "--profile")) {
            profile = true;
        } else if (std.mem.eql(u8, arg, "--bail")) {
            bail_on_error = true;
        } else if (std.mem.eql(u8, arg, "--config")) {
            i += 1;
            if (i >= args.len) fatal("--config requires value");
            config_path = args[i];
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

    // Auto-discover tsconfig if none specified
    const resolved_config_path = config_path orelse config.findTsConfig(io, alloc) orelse "tsconfig.json";
    defer if (config_path == null and !std.mem.eql(u8, resolved_config_path, "tsconfig.json")) alloc.free(resolved_config_path);

    if (config.readTsConfig(resolved_config_path, io, alloc) catch null) |ts| {
        try config.applyCompilerOptions(ts.compiler_options, &cfg);
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
        try std.Io.File.stdout().writeStreamingAll(io, usage);
        return;
    }
    if (input_paths.items.len > 1 and out_file != null) fatal("--out-file can only be used with a single input");
    if (delete_out_dir) {
        std.Io.Dir.cwd().deleteTree(io, out_dir orelse "dist") catch |err| {
            std.debug.print("warning: failed to delete out dir: {}\n", .{err});
        };
    }

    const start_time = std.Io.Timestamp.now(io, .awake).nanoseconds;
    var compiled: usize = 0;
    var errors: usize = 0;
    var total_lines: usize = 0;

    for (input_paths.items) |path| {
        const file_start = std.Io.Timestamp.now(io, .awake).nanoseconds;
        if (verbose) std.debug.print("compiling {s}...\n", .{path});
        cli.compilePath(path, .{ .out_file = out_file, .out_dir = out_dir, .config = cfg }, io, alloc) catch |err| {
            if (bail_on_error) {
                std.debug.print("error: failed to compile '{s}': {}\n", .{ path, err });
                std.process.exit(1);
            }
            std.debug.print("error: failed to compile '{s}': {}\n", .{ path, err });
            errors += 1;
            continue;
        };
        compiled += 1;
        if (profile) {
            const file_elapsed = @as(f64, @floatFromInt(std.Io.Timestamp.now(io, .awake).nanoseconds - file_start)) / 1_000_000.0;
            const source = std.Io.Dir.cwd().readFileAlloc(io, path, alloc, std.Io.Limit.limited(64 * 1024 * 1024)) catch null;
            var lines: usize = 0;
            if (source) |s| {
                defer alloc.free(s);
                for (s) |c| {
                    if (c == '\n') lines += 1;
                }
            }
            total_lines += lines;
            const color = if (file_elapsed < 10.0) "\x1b[32m" else if (file_elapsed < 50.0) "\x1b[33m" else "\x1b[31m";
            const reset = "\x1b[0m";
            std.debug.print("  {s}{d:.2}ms{s}  {s}  {d} lines\n", .{ color, file_elapsed, reset, std.fs.path.basename(path), lines });
        }
    }

    const elapsed = @as(f64, @floatFromInt(std.Io.Timestamp.now(io, .awake).nanoseconds - start_time)) / 1_000_000_000.0;
    if (compiled > 0) {
        std.debug.print("Compiled {d} file(s)", .{compiled});
        if (total_lines > 0) std.debug.print(", {d} lines", .{total_lines});
        std.debug.print(" in {d:.2}s", .{elapsed});
        if (errors > 0) std.debug.print(" ({d} errors)", .{errors});
        std.debug.print("\n", .{});
    }
}

fn fatal(msg: []const u8) noreturn {
    std.debug.print("error: {s}\n", .{msg});
    std.process.exit(1);
}
