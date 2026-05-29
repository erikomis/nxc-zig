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

    for (input_paths.items) |path| try cli.compilePath(path, .{ .out_file = out_file, .out_dir = out_dir, .config = cfg }, io, alloc);
}

fn fatal(msg: []const u8) noreturn {
    std.debug.print("error: {s}\n", .{msg});
    std.process.exit(1);
}
