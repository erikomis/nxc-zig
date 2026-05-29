const std = @import("std");

const cli = @import("cli");
const common = @import("common");
const linter = @import("linter");
const watch = @import("watch");

fn nowMs() i64 {
    var tp: std.os.linux.timespec = undefined;
    _ = std.os.linux.clock_gettime(std.os.linux.CLOCK.MONOTONIC, &tp);
    return @as(i64, tp.sec) * 1000 + @divTrunc(@as(i64, tp.nsec), 1_000_000);
}

const usage =
    \\nxc-formatter - format source files
    \\
    \\Usage:
    \\  nxc-formatter [--write] [--check] [--out-file <path>] [--config <path>] [--watch] [--verbose] [<file|dir> ...]
    \\
    \\If no paths given, formats all source files in the current directory recursively.
    \\
;

pub fn main(init: std.process.Init) !void {
    const alloc = init.gpa;
    const io = init.io;
    const args = try init.minimal.args.toSlice(alloc);
    defer alloc.free(args);

    var write = false;
    var check = false;
    var verbose = false;
    var enable_watch = false;
    var out_file: ?[]const u8 = null;
    var config_path: ?[]const u8 = null;
    var raw_paths = std.ArrayListUnmanaged([]const u8).empty;
    defer raw_paths.deinit(alloc);

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            try std.Io.File.stdout().writeStreamingAll(io, usage);
            return;
        } else if (std.mem.eql(u8, arg, "--write")) {
            write = true;
        } else if (std.mem.eql(u8, arg, "--check")) {
            check = true;
        } else if (std.mem.eql(u8, arg, "--watch")) {
            enable_watch = true;
        } else if (std.mem.eql(u8, arg, "--verbose")) {
            verbose = true;
        } else if (std.mem.eql(u8, arg, "--out-file")) {
            i += 1;
            if (i >= args.len) fatal("--out-file requires value");
            out_file = args[i];
        } else if (std.mem.eql(u8, arg, "--config")) {
            i += 1;
            if (i >= args.len) fatal("--config requires value");
            config_path = args[i];
        } else if (arg.len > 0 and arg[0] != '-') {
            try raw_paths.append(alloc, arg);
        } else {
            std.debug.print("unknown option: {s}\n", .{arg});
            std.process.exit(1);
        }
    }

    const paths = try expandPaths(raw_paths.items, io, alloc);
    defer {
        for (paths) |p| alloc.free(p);
        alloc.free(paths);
    }

    // --out-file only works with a single file input
    if (out_file != null and paths.len > 1) fatal("--out-file can only be used with a single input");

    const fmt_opts = loadFormatterConfig(config_path, io, alloc);

    if (enable_watch) {
        const fmt_watcher = FormatWatcher{ .opts = fmt_opts };
        try watch.watchFiles(paths, FormatWatcher, &fmt_watcher, io, alloc);
        return;
    }

    if (paths.len == 0) {
        try std.Io.File.stdout().writeStreamingAll(io, usage);
        return;
    }

    const start_time = nowMs();
var formatted_count: usize = 0;
var checked_count: usize = 0;

// Auto-write when: --write flag, no explicit paths given, or multiple files
const auto_write = write or raw_paths.items.len == 0 or (paths.len > 1 and out_file == null);

for (paths) |path| {
const file_start = nowMs();

const source = common.readFileAlloc(path, io, alloc) catch |err| {
std.debug.print("error: failed to read '{s}': {}\n", .{ path, err });
std.process.exit(1);
};
defer alloc.free(source);

const formatted = linter.format(source, fmt_opts, alloc) catch |err| {
std.debug.print("error: failed to format '{s}': {}\n", .{ path, err });
std.process.exit(1);
};
defer alloc.free(formatted);

const changed = !std.mem.eql(u8, source, formatted);

if (check) {
    if (changed) {
        std.debug.print("{s}\n", .{path});
        formatted_count += 1;
    } else {
        checked_count += 1;
    }
} else if (auto_write and changed) {
std.Io.Dir.cwd().writeFile(io, .{ .sub_path = out_file orelse path, .data = formatted }) catch |err| {
std.debug.print("error: failed to write '{s}': {}\n", .{ out_file orelse path, err });
std.process.exit(1);
};
} else if (out_file) |of| {
if (changed) {
std.Io.Dir.cwd().writeFile(io, .{ .sub_path = of, .data = formatted }) catch |err| {
std.debug.print("error: failed to write '{s}': {}\n", .{ of, err });
std.process.exit(1);
};
}
} else {
try std.Io.File.stdout().writeStreamingAll(io, formatted);
}

const elapsed_ms = nowMs() - file_start;
if (changed) {
formatted_count += 1;
if (verbose) std.debug.print("fixed {s} {d}ms\n", .{ path, elapsed_ms });
} else {
checked_count += 1;
if (verbose) std.debug.print("checked {s} {d}ms\n", .{ path, elapsed_ms });
}
}

const total_ms = nowMs() - start_time;
if (check) {
    if (formatted_count > 0) {
        std.debug.print("{d} file(s) need formatting\n", .{formatted_count});
        std.process.exit(1);
    } else {
        std.debug.print("All files formatted\n", .{});
    }
} else if (formatted_count > 0) {
std.debug.print("{d} file(s) formatted in {d}ms\n", .{ formatted_count, total_ms });
} else if (checked_count > 0) {
std.debug.print("No files changed\n", .{});
} else {
std.debug.print("No files changed\n", .{});
}
}

fn expandPaths(raw: []const []const u8, io: std.Io, alloc: std.mem.Allocator) ![][]const u8 {
    var result = std.ArrayListUnmanaged([]const u8).empty;
    errdefer {
        for (result.items) |p| alloc.free(p);
        result.deinit(alloc);
    }

    const entries = if (raw.len == 0) blk: {
        var single = try alloc.alloc([]const u8, 1);
        single[0] = ".";
        break :blk single;
    } else raw;

    for (entries) |entry| {
        switch (cli.classifyInputPath(entry, io)) {
            .file => try result.append(alloc, try alloc.dupe(u8, entry)),
            .directory => {
                const files = try cli.collectFiles(entry, io, alloc);
                for (files) |f| try result.append(alloc, f);
                alloc.free(files);
            },
            .missing => {
                std.debug.print("error: path not found: {s}\n", .{entry});
                std.process.exit(1);
            },
        }
    }

    if (raw.len == 0) alloc.free(entries);
    return result.toOwnedSlice(alloc);
}

fn loadFormatterConfig(config_path: ?[]const u8, io: std.Io, alloc: std.mem.Allocator) common.FormatterOptions {
    const fmt_cfg = if (config_path) |path|
        linter.readAndParseFormatterConfig(path, io, alloc) catch linter.FormatterConfig{}
    else
        blk: {
            const cfg = linter.searchConfigCwd(io, alloc);
            break :blk cfg.formatter;
        };
    return fmt_cfg.options;
}

fn fatal(msg: []const u8) noreturn {
    std.debug.print("error: {s}\n", .{msg});
    std.process.exit(1);
}

const FormatWatcher = struct {
    opts: common.FormatterOptions,

    pub fn onChange(self: *const FormatWatcher, path: []const u8, io: std.Io, alloc: std.mem.Allocator) !void {
        const source = common.readFileAlloc(path, io, alloc) catch |err| {
            std.debug.print("  error reading {s}: {}\n", .{ path, err });
            return;
        };
        defer alloc.free(source);
        const formatted = linter.format(source, self.opts, alloc) catch |err| {
            std.debug.print("  error formatting {s}: {}\n", .{ path, err });
            return;
        };
        defer alloc.free(formatted);
        if (!std.mem.eql(u8, source, formatted)) {
            std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = formatted }) catch |err| {
                std.debug.print("  error writing {s}: {}\n", .{ path, err });
            };
        }
    }
};
