const std = @import("std");
const compiler = @import("compiler");
const Diag = @import("diagnostics");

pub const InputKind = enum { file, directory, missing };

pub fn isTranspilable(name: []const u8) bool {
    if (std.mem.endsWith(u8, name, ".d.ts")) return false;
    if (std.mem.endsWith(u8, name, ".d.mts")) return false;
    if (std.mem.endsWith(u8, name, ".d.cts")) return false;
    return std.mem.endsWith(u8, name, ".ts") or
        std.mem.endsWith(u8, name, ".tsx") or
        std.mem.endsWith(u8, name, ".mts") or
        std.mem.endsWith(u8, name, ".cts") or
        std.mem.endsWith(u8, name, ".jsx");
}

pub fn isCopyableJs(name: []const u8) bool {
    return std.mem.endsWith(u8, name, ".js") or
        std.mem.endsWith(u8, name, ".mjs") or
        std.mem.endsWith(u8, name, ".cjs");
}

pub fn isCompilable(name: []const u8) bool {
    return isTranspilable(name) or isCopyableJs(name);
}

const defaultIgnored = [_][]const u8{
    "node_modules",
    "dist",
    "coverage",
    "build",
    "out",
};

fn isDefaultIgnoredComponent(component: []const u8, has_more_components: bool) bool {
    for (defaultIgnored) |dir| {
        if (std.mem.eql(u8, component, dir)) return true;
    }

    // Hidden directories like .git, .vscode, .next, etc.
    // Only ignore dot-prefixed path components when they are directories,
    // not root-level files like .eslintrc.ts.
    return has_more_components and component.len > 1 and component[0] == '.';
}

pub fn isDefaultIgnored(path: []const u8) bool {
    var start: usize = 0;
    while (start < path.len) {
        while (start < path.len and (path[start] == '/' or path[start] == '\\')) : (start += 1) {}
        if (start >= path.len) break;

        var end = start;
        while (end < path.len and path[end] != '/' and path[end] != '\\') : (end += 1) {}

        const component = path[start..end];
        const has_more_components = end < path.len;
        if (isDefaultIgnoredComponent(component, has_more_components)) return true;

        start = end + 1;
    }

    return false;
}

/// Compute output path for src_file given a src_root and out_dir.
/// Strips src_root prefix from src_file, then changes extension to .js.
pub fn buildOutPath(src_file: []const u8, src_root: []const u8, out_dir: []const u8, alloc: std.mem.Allocator) ![]u8 {
    const root = std.mem.trimEnd(u8, src_root, "/");
    const out = std.mem.trimEnd(u8, out_dir, "/");

    var rel: []const u8 = std.fs.path.basename(src_file);
    if (std.mem.startsWith(u8, src_file, root)) {
        const after = src_file[root.len..];
        const trimmed = std.mem.trimStart(u8, after, "/");
        if (trimmed.len > 0) rel = trimmed;
    }

    const dot = std.mem.lastIndexOfScalar(u8, rel, '.');
    const stem = if (dot) |d| rel[0..d] else rel;

    return std.fmt.allocPrint(alloc, "{s}/{s}.js", .{ out, stem });
}

pub fn buildCopyOutPath(src_file: []const u8, src_root: []const u8, out_dir: []const u8, alloc: std.mem.Allocator) ![]u8 {
    const root = std.mem.trimEnd(u8, src_root, "/");
    const out = std.mem.trimEnd(u8, out_dir, "/");

    var rel: []const u8 = std.fs.path.basename(src_file);
    if (std.mem.startsWith(u8, src_file, root)) {
        const after = src_file[root.len..];
        const trimmed = std.mem.trimStart(u8, after, "/");
        if (trimmed.len > 0) rel = trimmed;
    }

    return std.fmt.allocPrint(alloc, "{s}/{s}", .{ out, rel });
}

pub fn buildMapPath(out_path: []const u8, alloc: std.mem.Allocator) ![]u8 {
    return std.fmt.allocPrint(alloc, "{s}.map", .{out_path});
}

pub fn appendSourceMapComment(code: []const u8, out_path: []const u8, alloc: std.mem.Allocator) ![]u8 {
    const map_path = try buildMapPath(out_path, alloc);
    defer alloc.free(map_path);
    return std.fmt.allocPrint(alloc, "{s}\n//# sourceMappingURL={s}", .{ code, std.fs.path.basename(map_path) });
}

pub fn appendInlineSourceMapComment(code: []const u8, map: []const u8, alloc: std.mem.Allocator) ![]u8 {
    const encoded = try base64Encode(map, alloc);
    defer alloc.free(encoded);
    return std.fmt.allocPrint(alloc, "{s}\n//# sourceMappingURL=data:application/json;charset=utf-8;base64,{s}", .{ code, encoded });
}

pub fn classifyInputPath(path: []const u8, io: std.Io) InputKind {
    const stat = std.Io.Dir.cwd().statFile(io, path, .{}) catch return .missing;
    return if (stat.kind == .directory) .directory else .file;
}

pub fn compileInput(path: []const u8, out_file: ?[]const u8, out_dir: ?[]const u8, cfg: compiler.Config, io: std.Io, alloc: std.mem.Allocator) !void {
    switch (classifyInputPath(path, io)) {
        .missing => return error.FileNotFound,
        .directory => {
            const od = out_dir orelse return error.MissingOutDir;
            try compileDirAll(path, od, cfg, io, alloc);
        },
        .file => {
            if (isCopyableJs(std.fs.path.basename(path))) {
                try copySingle(path, path, out_file, out_dir, io, alloc);
                return;
            }

            var file_cfg = cfg;
            if (std.mem.endsWith(u8, path, ".jsx") or std.mem.endsWith(u8, path, ".tsx")) file_cfg.jsx = true;
            try compileSingle(path, path, out_file, out_dir, file_cfg, io, alloc);
        },
    }
}

/// Collect all compilable files in dir_path recursively. Caller frees each string and the slice.
pub fn collectFiles(dir_path: []const u8, io: std.Io, alloc: std.mem.Allocator) ![][]const u8 {
    var result = std.ArrayListUnmanaged([]const u8).empty;
    errdefer {
        for (result.items) |f| alloc.free(f);
        result.deinit(alloc);
    }

    var dir = try std.Io.Dir.cwd().openDir(io, dir_path, .{ .iterate = true });
    defer dir.close(io);
    var walker = try dir.walk(alloc);
    defer walker.deinit();

    while (try walker.next(io)) |entry| {
        if (isDefaultIgnored(entry.path)) continue;
        if (entry.kind != .file) continue;
        if (!isCompilable(entry.basename)) continue;
        const full = try std.fs.path.join(alloc, &.{ dir_path, entry.path });
        try result.append(alloc, full);
    }

    return result.toOwnedSlice(alloc);
}

/// Compile all compilable files in src_dir into out_dir, preserving subdirectory structure.
pub fn compileDirAll(src_dir: []const u8, out_dir: []const u8, cfg: compiler.Config, io: std.Io, alloc: std.mem.Allocator) !void {
    const files = try collectFiles(src_dir, io, alloc);
    defer {
        for (files) |f| alloc.free(f);
        alloc.free(files);
    }

    for (files) |src_file| {
        const base = std.fs.path.basename(src_file);

        if (isCopyableJs(base)) {
            copySingle(src_file, src_dir, null, out_dir, io, alloc) catch |err| {
                switch (err) {
                    error.IsDir => std.debug.print("error copying {s}: expected a file path, but received a directory\n", .{src_file}),
                    error.FileNotFound => std.debug.print("error copying {s}: file not found\n", .{src_file}),
                    else => std.debug.print("error copying {s}: {}\n", .{ src_file, err }),
                }
            };
            continue;
        }

        var file_cfg = cfg;
        if (std.mem.endsWith(u8, base, ".jsx") or std.mem.endsWith(u8, base, ".tsx")) {
            file_cfg.jsx = true;
        }

        const out_path = try buildOutPath(src_file, src_dir, out_dir, alloc);
        defer alloc.free(out_path);

        if (std.fs.path.dirname(out_path)) |dir| {
            makeDirAll(dir, io) catch |err| {
                std.debug.print("warning: failed to create dir {s}: {}\n", .{ dir, err });
            };
        }

        compileSingle(src_file, src_dir, null, out_dir, file_cfg, io, alloc) catch |err| {
            switch (err) {
                error.IsDir => std.debug.print("error compiling {s}: expected a file path, but received a directory\n", .{src_file}),
                error.FileNotFound => std.debug.print("error compiling {s}: file not found\n", .{src_file}),
                else => std.debug.print("error compiling {s}: {}\n", .{ src_file, err }),
            }
        };
    }
}

fn readFileAlloc(path: []const u8, io: std.Io, alloc: std.mem.Allocator) ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(io, path, alloc, .unlimited);
}

pub fn copySingle(src_file: []const u8, src_root: []const u8, out_file: ?[]const u8, out_dir: ?[]const u8, io: std.Io, alloc: std.mem.Allocator) !void {
    const data = try readFileAlloc(src_file, io, alloc);
    defer alloc.free(data);

    if (out_file) |of| {
        if (std.fs.path.dirname(of)) |dir| {
            makeDirAll(dir, io) catch |err| {
                std.debug.print("warning: failed to create dir {s}: {}\n", .{ dir, err });
            };
        }
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = of, .data = data });
    } else if (out_dir) |od| {
        const out_path = try buildCopyOutPath(src_file, src_root, od, alloc);
        defer alloc.free(out_path);

        if (std.fs.path.dirname(out_path)) |dir| {
            makeDirAll(dir, io) catch |err| {
                std.debug.print("warning: failed to create dir {s}: {}\n", .{ dir, err });
            };
        }

        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = out_path, .data = data });
    } else {
        try std.Io.File.stdout().writeStreamingAll(io, data);
    }
}

pub fn compileSingle(src_file: []const u8, src_root: []const u8, out_file: ?[]const u8, out_dir: ?[]const u8, cfg: compiler.Config, io: std.Io, alloc: std.mem.Allocator) !void {
    const result = try compiler.compileFile(src_file, cfg, io, alloc);
    defer result.deinit(alloc);

    Diag.printDiagnostics(result.diagnostics);

    if (cfg.no_emit) return;

    const emit_js = !cfg.emit_declaration_only;

    if (out_file) |of| {
        if (std.fs.path.dirname(of)) |dir| {
            makeDirAll(dir, io) catch |err| {
                std.debug.print("warning: failed to create dir {s}: {}\n", .{ dir, err });
            };
        }

        if (emit_js) {
            if (result.map) |map| {
                if (cfg.inline_source_map) {
                    const code_with_comment = try appendInlineSourceMapComment(result.code, map, alloc);
                    defer alloc.free(code_with_comment);
                    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = of, .data = code_with_comment });
                } else {
                    const map_path = try buildMapPath(of, alloc);
                    defer alloc.free(map_path);
                    const code_with_comment = try appendSourceMapComment(result.code, of, alloc);
                    defer alloc.free(code_with_comment);
                    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = of, .data = code_with_comment });
                    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = map_path, .data = map });
                }
            } else {
                try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = of, .data = result.code });
            }
        }

        if (result.declarations) |dts| {
            const dts_path = if (cfg.declaration_dir) |dd| blk: {
                const base = std.fs.path.basename(of);
                break :blk try std.fs.path.join(alloc, &.{ dd, base });
            } else try compiler.declarationPathFromJsPath(alloc, of);
            defer alloc.free(dts_path);

            if (std.fs.path.dirname(dts_path)) |dir| {
                makeDirAll(dir, io) catch |err| {
                    std.debug.print("warning: failed to create dir {s}: {}\n", .{ dir, err });
                };
            }

            try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = dts_path, .data = dts });
        }
    } else if (out_dir) |od| {
        const out_path = try buildOutPath(src_file, src_root, od, alloc);
        defer alloc.free(out_path);
        if (std.fs.path.dirname(out_path)) |dir| {
            makeDirAll(dir, io) catch |err| {
                std.debug.print("warning: failed to create dir {s}: {}\n", .{ dir, err });
            };
        }
        if (emit_js) {
            if (result.map) |map| {
                if (cfg.inline_source_map) {
                    const code_with_comment = try appendInlineSourceMapComment(result.code, map, alloc);
                    defer alloc.free(code_with_comment);
                    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = out_path, .data = code_with_comment });
                } else {
                    const map_path = try buildMapPath(out_path, alloc);
                    defer alloc.free(map_path);
                    const code_with_comment = try appendSourceMapComment(result.code, out_path, alloc);
                    defer alloc.free(code_with_comment);
                    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = out_path, .data = code_with_comment });
                    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = map_path, .data = map });
                }
            } else {
                try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = out_path, .data = result.code });
            }
        }
        if (result.declarations) |dts| {
            const dts_path = if (cfg.declaration_dir) |dd| blk: {
                const base = std.fs.path.basename(out_path);
                break :blk try std.fs.path.join(alloc, &.{ dd, base });
            } else try compiler.declarationPathFromJsPath(alloc, out_path);
            defer alloc.free(dts_path);

            if (std.fs.path.dirname(dts_path)) |dir| {
                makeDirAll(dir, io) catch |err| {
                    std.debug.print("warning: failed to create dir {s}: {}\n", .{ dir, err });
                };
            }

            try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = dts_path, .data = dts });
        }
    } else if (emit_js) {
        try std.Io.File.stdout().writeStreamingAll(io, result.code);
    }
}

fn makeDirAll(path: []const u8, io: std.Io) !void {
    try std.Io.Dir.cwd().createDirPath(io, path);
}

const base64_alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

fn base64Encode(data: []const u8, alloc: std.mem.Allocator) ![]u8 {
    const out_len = (data.len + 2) / 3 * 4;
    var out = try alloc.alloc(u8, out_len);
    var i: usize = 0;
    var j: usize = 0;
    while (i + 2 < data.len) : (i += 3) {
        out[j] = base64_alphabet[data[i] >> 2];
        out[j + 1] = base64_alphabet[((data[i] & 3) << 4) | (data[i + 1] >> 4)];
        out[j + 2] = base64_alphabet[((data[i + 1] & 15) << 2) | (data[i + 2] >> 6)];
        out[j + 3] = base64_alphabet[data[i + 2] & 63];
        j += 4;
    }
    if (i < data.len) {
        out[j] = base64_alphabet[data[i] >> 2];
        if (i + 1 < data.len) {
            out[j + 1] = base64_alphabet[((data[i] & 3) << 4) | (data[i + 1] >> 4)];
            out[j + 2] = base64_alphabet[(data[i + 1] & 15) << 2];
            out[j + 3] = '=';
        } else {
            out[j + 1] = base64_alphabet[(data[i] & 3) << 4];
            out[j + 2] = '=';
            out[j + 3] = '=';
        }
    }
    return out;
}
