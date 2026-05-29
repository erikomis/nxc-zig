const std = @import("std");
const compiler = @import("compiler");
const incremental = @import("incremental");
const old_cli = @import("old_cli");

const Io = std.Io;

pub fn watchAndCompile(
    paths: []const []const u8,
    cfg: compiler.Config,
    out_dir: ?[]const u8,
    out_file: ?[]const u8,
    io: Io,
    alloc: std.mem.Allocator,
) !void {
    var inc = incremental.IncrementalCompiler.init("dist/.cache", cfg);
    defer inc.deinit(io, alloc);
    try inc.load(io, alloc);

    try initialCompile(paths, cfg, out_dir, out_file, io, alloc);

    {
        var buf: [9]u8 = undefined;
        std.debug.print("[{s}] Watching for changes...\n", .{fmtTimestamp(&buf, io)});
    }

    var mtimes = std.StringHashMapUnmanaged(i128).empty;
    defer {
        var it = mtimes.keyIterator();
        while (it.next()) |k| alloc.free(k.*);
        mtimes.deinit(alloc);
    }

    try collectInitialFiles(paths, &mtimes, io, alloc);

    var debounce: i128 = 0;
    var poll_tick: u32 = 0;
    var pending = std.ArrayListUnmanaged([]const u8).empty;
    defer {
        for (pending.items) |p| alloc.free(p);
        pending.deinit(alloc);
    }

    while (true) {
        std.Io.sleep(io, .{ .nanoseconds = std.time.ns_per_s }, .awake) catch continue;
        poll_tick += 1;

        var changed = false;

        // Check for deleted files (every 2 ticks to reduce stat overhead)
        if (poll_tick % 2 == 1) {
            var to_remove = std.ArrayListUnmanaged([]const u8).empty;
            defer {
                for (to_remove.items) |k| alloc.free(k);
                to_remove.deinit(alloc);
            }

            {
                var it = mtimes.iterator();
                while (it.next()) |entry| {
                    if (Io.Dir.cwd().statFile(io, entry.key_ptr.*, .{})) |_| {} else |_| {
                        var buf: [9]u8 = undefined;
                        std.debug.print("[{s}] Deleted: {s}\n", .{ fmtTimestamp(&buf, io), entry.key_ptr.* });
                        const dup = try alloc.dupe(u8, entry.key_ptr.*);
                        try to_remove.append(alloc, dup);
                        changed = true;
                    }
                }
            }

            for (to_remove.items) |path| {
                _ = mtimes.remove(path);
            }
        }

        // Check for modified files (every 2 ticks)
        if (poll_tick % 2 == 1) {
            var it = mtimes.iterator();
            while (it.next()) |entry| {
                const stat = Io.Dir.cwd().statFile(io, entry.key_ptr.*, .{}) catch continue;
                const mtime = stat.mtime.nanoseconds;
                if (mtime == entry.value_ptr.*) continue;
                entry.value_ptr.* = mtime;
                var buf: [9]u8 = undefined;
                std.debug.print("[{s}] Changed: {s}\n", .{ fmtTimestamp(&buf, io), entry.key_ptr.* });
                try pending.append(alloc, try alloc.dupe(u8, entry.key_ptr.*));
                changed = true;
            }
        }

        // Check for new files in directories (every 4 ticks, which is less frequent)
        if (poll_tick % 4 == 1) {
            for (paths) |path| {
                if (old_cli.classifyInputPath(path, io) != .directory) continue;
                const files = old_cli.collectFiles(path, io, alloc) catch continue;
                defer {
                    for (files) |f| alloc.free(f);
                    alloc.free(files);
                }
                for (files) |f| {
                    if (mtimes.contains(f)) continue;
                    const stat = Io.Dir.cwd().statFile(io, f, .{}) catch continue;
                    const key = try alloc.dupe(u8, f);
                    try mtimes.put(alloc, key, stat.mtime.nanoseconds);
                    var buf: [9]u8 = undefined;
                    std.debug.print("[{s}] New: {s}\n", .{ fmtTimestamp(&buf, io), f });
                    changed = true;
                }
            }
        }

        if (changed) {
            debounce = std.Io.Timestamp.now(io, .awake).nanoseconds;
        } else if (debounce > 0) {
            const elapsed = @as(i128, std.Io.Timestamp.now(io, .awake).nanoseconds) - debounce;
            if (elapsed >= 100 * std.time.ns_per_ms) {
                debounce = 0;
                // Incremental compile: only recompile files that truly changed
                for (pending.items) |path| {
                    const result = inc.compileFile(path, io, alloc) catch |err| {
                        std.debug.print("error: failed to compile '{s}': {}\n", .{ path, err });
                        continue;
                    };
                    alloc.free(result.code);
                    if (result.map) |m| alloc.free(m);
                    if (result.declarations) |d| alloc.free(d);
                    for (result.diagnostics) |d| {
                        alloc.free(d.message);
                        alloc.free(d.filename);
                        if (d.source_line) |l| alloc.free(l);
                    }
                    alloc.free(result.diagnostics);
                }
                for (pending.items) |p| alloc.free(p);
                pending.clearRetainingCapacity();
                var buf: [9]u8 = undefined;
                std.debug.print("[{s}] Watching for changes...\n", .{fmtTimestamp(&buf, io)});
            }
        }
    }
}

fn fmtTimestamp(buf: []u8, io: Io) []const u8 {
    const now = std.Io.Timestamp.now(io, .real);
    const seconds: u64 = @intCast(@divTrunc(@as(i128, now.nanoseconds), std.time.ns_per_s));
    const t = seconds % 86400;
    return std.fmt.bufPrint(buf, "{d:0>2}:{d:0>2}:{d:0>2}", .{
        t / 3600,
        (t / 60) % 60,
        t % 60,
    }) catch "??:??:??";
}

fn initialCompile(
    paths: []const []const u8,
    cfg: compiler.Config,
    out_dir: ?[]const u8,
    out_file: ?[]const u8,
    io: Io,
    alloc: std.mem.Allocator,
) !void {
    _ = out_file;
    for (paths) |path| {
        switch (old_cli.classifyInputPath(path, io)) {
            .directory => {
                old_cli.compileInput(path, null, out_dir orelse "dist", cfg, io, alloc) catch |err| {
                    std.debug.print("error: failed to compile '{s}': {}\n", .{ path, err });
                };
            },
            .file => {
                old_cli.compileInput(path, null, out_dir, cfg, io, alloc) catch |err| {
                    std.debug.print("error: failed to compile '{s}': {}\n", .{ path, err });
                };
            },
            .missing => {
                std.debug.print("error: failed to compile '{s}': file not found\n", .{ path });
            },
        }
    }
    }

fn collectInitialFiles(
    paths: []const []const u8,
    mtimes: *std.StringHashMapUnmanaged(i128),
    io: Io,
    alloc: std.mem.Allocator,
) !void {
    for (paths) |path| {
        switch (old_cli.classifyInputPath(path, io)) {
            .file => {
                const stat = try Io.Dir.cwd().statFile(io, path, .{});
                const key = try alloc.dupe(u8, path);
                try mtimes.put(alloc, key, stat.mtime.nanoseconds);
            },
            .directory => {
                const files = try old_cli.collectFiles(path, io, alloc);
                defer {
                    for (files) |f| alloc.free(f);
                    alloc.free(files);
                }
                for (files) |f| {
                    const stat = Io.Dir.cwd().statFile(io, f, .{}) catch continue;
                    const key = try alloc.dupe(u8, f);
                    try mtimes.put(alloc, key, stat.mtime.nanoseconds);
                }
            },
            .missing => {},
        }
    }
}

pub fn watchFiles(
    paths: []const []const u8,
    comptime Watcher: type,
    watcher: *const Watcher,
    io: Io,
    alloc: std.mem.Allocator,
) !void {
    {
        var buf: [9]u8 = undefined;
        std.debug.print("[{s}] Watching for changes...\n", .{fmtTimestamp(&buf, io)});
    }

    var mtimes = std.StringHashMapUnmanaged(i128).empty;
    defer {
        var it = mtimes.keyIterator();
        while (it.next()) |k| alloc.free(k.*);
        mtimes.deinit(alloc);
    }

    try collectInitialFiles(paths, &mtimes, io, alloc);

    var poll_tick: u32 = 0;

    while (true) {
        std.Io.sleep(io, .{ .nanoseconds = std.time.ns_per_s }, .awake) catch continue;
        poll_tick += 1;

        // Check for deleted files
        if (poll_tick % 2 == 1) {
            var to_remove = std.ArrayListUnmanaged([]const u8).empty;
            defer {
                for (to_remove.items) |k| alloc.free(k);
                to_remove.deinit(alloc);
            }

            {
                var it = mtimes.iterator();
                while (it.next()) |entry| {
                    if (Io.Dir.cwd().statFile(io, entry.key_ptr.*, .{})) |_| {} else |_| {
                        var buf: [9]u8 = undefined;
                        std.debug.print("[{s}] Deleted: {s}\n", .{ fmtTimestamp(&buf, io), entry.key_ptr.* });
                        const dup = try alloc.dupe(u8, entry.key_ptr.*);
                        try to_remove.append(alloc, dup);
                    }
                }
            }

            for (to_remove.items) |path| {
                _ = mtimes.remove(path);
            }
        }

        // Check for modified files
        if (poll_tick % 2 == 1) {
            var it = mtimes.iterator();
            while (it.next()) |entry| {
                const stat = Io.Dir.cwd().statFile(io, entry.key_ptr.*, .{}) catch continue;
                const mtime = stat.mtime.nanoseconds;
                if (mtime == entry.value_ptr.*) continue;
                entry.value_ptr.* = mtime;
                var buf: [9]u8 = undefined;
                std.debug.print("[{s}] Changed: {s}\n", .{ fmtTimestamp(&buf, io), entry.key_ptr.* });
                watcher.onChange(entry.key_ptr.*, io, alloc) catch |err| {
                    std.debug.print("[{s}] Error: {}\n", .{ fmtTimestamp(&buf, io), err });
                };
            }
        }

        // Check for new files
        if (poll_tick % 4 == 1) {
            for (paths) |path| {
                if (old_cli.classifyInputPath(path, io) != .directory) continue;
                const files = old_cli.collectFiles(path, io, alloc) catch continue;
                defer {
                    for (files) |f| alloc.free(f);
                    alloc.free(files);
                }
                for (files) |f| {
                    if (mtimes.contains(f)) continue;
                    const stat = Io.Dir.cwd().statFile(io, f, .{}) catch continue;
                    const key = try alloc.dupe(u8, f);
                    try mtimes.put(alloc, key, stat.mtime.nanoseconds);
                    var buf: [9]u8 = undefined;
                    std.debug.print("[{s}] New: {s}\n", .{ fmtTimestamp(&buf, io), f });
                    watcher.onChange(f, io, alloc) catch |err| {
                        std.debug.print("[{s}] Error: {}\n", .{ fmtTimestamp(&buf, io), err });
                    };
                }
            }
        }
    }
}
