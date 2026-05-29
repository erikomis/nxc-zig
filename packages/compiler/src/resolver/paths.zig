const std = @import("std");
const ast = @import("parser").ast;

pub const FullPathsConfig = struct {
    /// Append .js/.mjs to relative imports with no runtime extension.
    add_js_extension: bool = false,
    /// Source file path, for example "src/app.ts". Used to make baseUrl results relative to this file.
    src_file: []const u8 = "",
    /// Source directory used to probe relative imports on disk.
    src_dir: []const u8 = "",
    /// tsconfig baseUrl. Bare specifiers are resolved relative to this directory when they exist on disk.
    base_url: ?[]const u8 = null,
};

/// Transform import/export/dynamic-import string literals by resolving full paths only.
/// This does not resolve aliases; keep that responsibility in aliases.zig.
pub fn resolveFullPaths(
    arena: *ast.Arena,
    alloc: std.mem.Allocator,
    io: std.Io,
    cfg: FullPathsConfig,
) !void {
    if (!cfg.add_js_extension and cfg.base_url == null) return;

    const nodes = arena.nodes.items;
    for (0..nodes.len) |i| {
        switch (nodes[i]) {
            .import_decl => |n| try rewriteSourceFullPath(arena, alloc, io, cfg, n.source),
            .export_decl => |n| switch (n.kind) {
                .named => |e| if (e.source) |s| try rewriteSourceFullPath(arena, alloc, io, cfg, s),
                .all => |e| try rewriteSourceFullPath(arena, alloc, io, cfg, e.source),
                else => {},
            },
            .import_call => |n| try rewriteSourceFullPath(arena, alloc, io, cfg, n.source),
            else => {},
        }
    }
}

/// Resolve a single import specifier using only full-path rules:
/// - baseUrl for existing bare specifiers
/// - node_modules lookup for bare specifiers
/// - .ts/.tsx/.mts/.cts to runtime .js/.mjs
/// - extension probing for extensionless relative specifiers
pub fn resolveFullPath(
    specifier: []const u8,
    io: std.Io,
    cfg: FullPathsConfig,
    alloc: std.mem.Allocator,
) ![]const u8 {
    var value = specifier;

    if (isBareSpecifier(value)) {
        if (cfg.base_url) |base| {
            const bare_path = try std.fs.path.join(alloc, &.{ base, value });
            if (try probeExtension(bare_path, ".", io, alloc)) |resolved_path| {
                const dotslash = try std.fmt.allocPrint(alloc, "./{s}", .{resolved_path});
                value = try makeRelativeToSrcFile(dotslash, cfg.src_file, alloc);
                return value;
            } else if (try pathExists(bare_path, io)) {
                const dotslash = try std.fmt.allocPrint(alloc, "./{s}", .{bare_path});
                value = try makeRelativeToSrcFile(dotslash, cfg.src_file, alloc);
                return value;
            }
        }

        // Try node_modules resolution
        if (try resolveNodeModules(value, cfg.src_file, io, alloc)) |resolved| {
            return resolved;
        }
    }

    if (cfg.add_js_extension and isRelativeSpecifier(value)) {
        value = try resolveImportPath(value, cfg.src_dir, io, alloc) orelse value;
    }

    return value;
}

fn rewriteSourceFullPath(
    arena: *ast.Arena,
    alloc: std.mem.Allocator,
    io: std.Io,
    cfg: FullPathsConfig,
    source_id: ast.NodeId,
) !void {
    const node = arena.getMut(source_id);
    const lit = switch (node.*) {
        .str_lit => |*s| s,
        else => return,
    };

    const value = try resolveFullPath(lit.value, io, cfg, alloc);
    if (std.mem.eql(u8, value, lit.value)) return;

    lit.value = value;
    lit.raw = try std.fmt.allocPrint(alloc, "\"{s}\"", .{value});
}

fn isBareSpecifier(path: []const u8) bool {
    const path_only = splitSuffix(path).path;
    if (path_only.len == 0) return false;
    if (isRelative(path_only)) return false;
    if (path_only[0] == '/') return false;
    if (std.mem.indexOf(u8, path_only, ":") != null) return false;
    return true;
}

fn isRelativeSpecifier(path: []const u8) bool {
    return isRelative(splitSuffix(path).path);
}

fn isRelative(path: []const u8) bool {
    return std.mem.eql(u8, path, ".") or
        std.mem.eql(u8, path, "..") or
        std.mem.startsWith(u8, path, "./") or
        std.mem.startsWith(u8, path, "../");
}

fn resolveImportPath(specifier: []const u8, src_dir: []const u8, io: std.Io, alloc: std.mem.Allocator) !?[]const u8 {
    const parts = splitSuffix(specifier);

    if (hasJsExtension(parts.path)) return null;

    if (try tsExtToJs(parts.path, alloc)) |resolved| {
        if (parts.suffix.len == 0) return resolved;

        defer alloc.free(resolved);
        return try std.fmt.allocPrint(alloc, "{s}{s}", .{ resolved, parts.suffix });
    }

    if (needsExtension(parts.path)) {
        if (try probeExtension(parts.path, src_dir, io, alloc)) |resolved| {
            if (parts.suffix.len == 0) return resolved;

            defer alloc.free(resolved);
            return try std.fmt.allocPrint(alloc, "{s}{s}", .{ resolved, parts.suffix });
        }
    }

    return null;
}

fn splitSuffix(specifier: []const u8) struct { path: []const u8, suffix: []const u8 } {
    const query_idx = std.mem.indexOfScalar(u8, specifier, '?');
    const hash_idx = std.mem.indexOfScalar(u8, specifier, '#');

    var split_at = specifier.len;
    if (query_idx) |idx| split_at = @min(split_at, idx);
    if (hash_idx) |idx| split_at = @min(split_at, idx);

    return .{
        .path = specifier[0..split_at],
        .suffix = specifier[split_at..],
    };
}

fn tsExtToJs(path: []const u8, alloc: std.mem.Allocator) !?[]const u8 {
    if (std.mem.endsWith(u8, path, ".mts")) return try std.fmt.allocPrint(alloc, "{s}.mjs", .{path[0 .. path.len - 4]});
    if (std.mem.endsWith(u8, path, ".cts")) return try std.fmt.allocPrint(alloc, "{s}.js", .{path[0 .. path.len - 4]});
    if (std.mem.endsWith(u8, path, ".tsx")) return try std.fmt.allocPrint(alloc, "{s}.js", .{path[0 .. path.len - 4]});
    if (std.mem.endsWith(u8, path, ".ts")) return try std.fmt.allocPrint(alloc, "{s}.js", .{path[0 .. path.len - 3]});
    return null;
}

fn probeExtension(path: []const u8, src_dir: []const u8, io: std.Io, alloc: std.mem.Allocator) !?[]const u8 {
    const candidates = [_]struct {
        fs_suffix: []const u8,
        out_suffix: []const u8,
    }{
        .{ .fs_suffix = ".ts", .out_suffix = ".js" },
        .{ .fs_suffix = ".tsx", .out_suffix = ".js" },
        .{ .fs_suffix = ".mts", .out_suffix = ".mjs" },
        .{ .fs_suffix = ".cts", .out_suffix = ".js" },
        .{ .fs_suffix = ".js", .out_suffix = ".js" },
        .{ .fs_suffix = ".mjs", .out_suffix = ".mjs" },
        .{ .fs_suffix = "/index.ts", .out_suffix = "/index.js" },
        .{ .fs_suffix = "/index.tsx", .out_suffix = "/index.js" },
        .{ .fs_suffix = "/index.mts", .out_suffix = "/index.mjs" },
        .{ .fs_suffix = "/index.cts", .out_suffix = "/index.js" },
    };

    for (candidates) |candidate| {
        const relative_probe = try std.fmt.allocPrint(alloc, "{s}{s}", .{ path, candidate.fs_suffix });
        defer alloc.free(relative_probe);

        const full_probe = try std.fs.path.join(alloc, &.{ src_dir, relative_probe });
        defer alloc.free(full_probe);

        if (try pathExists(full_probe, io)) {
            return try std.fmt.allocPrint(alloc, "{s}{s}", .{ path, candidate.out_suffix });
        }
    }

    return null;
}

fn pathExists(path: []const u8, io: std.Io) !bool {
    _ = std.Io.Dir.cwd().statFile(io, path, .{}) catch |err| switch (err) {
        error.FileNotFound, error.NotDir => return false,
        else => return err,
    };
    return true;
}

fn appendSuffix(path: []const u8, suffix: []const u8, alloc: std.mem.Allocator) ![]const u8 {
    if (suffix.len == 0) return path;
    return try std.fmt.allocPrint(alloc, "{s}{s}", .{ path, suffix });
}

fn hasJsExtension(path: []const u8) bool {
    return std.mem.endsWith(u8, path, ".js") or std.mem.endsWith(u8, path, ".mjs");
}

fn isKnownExtension(ext: []const u8) bool {
    const known = [_][]const u8{ "js", "mjs", "ts", "tsx", "mts", "cts", "json", "node" };
    for (known) |k| if (std.mem.eql(u8, ext, k)) return true;
    return false;
}

fn needsExtension(path: []const u8) bool {
    const base = std.fs.path.basename(path);
    const dot = std.mem.lastIndexOfScalar(u8, base, '.') orelse return true;
    return !isKnownExtension(base[dot + 1 ..]);
}

fn makeRelativeToSrcFile(path: []const u8, src_file: []const u8, alloc: std.mem.Allocator) ![]const u8 {
    if (src_file.len == 0) return path;
    if (!std.mem.startsWith(u8, path, "./") and !std.mem.startsWith(u8, path, "../")) return path;

    const src_dir = std.fs.path.dirname(src_file) orelse return path;
    if (src_dir.len == 0 or std.mem.eql(u8, src_dir, ".")) return path;

    const to_normalized = if (std.mem.startsWith(u8, path, "./")) path[2..] else path;
    return relPath(src_dir, to_normalized, alloc);
}

fn relPath(from_dir: []const u8, to: []const u8, alloc: std.mem.Allocator) ![]const u8 {
    var from_buf: [256][]const u8 = undefined;
    var to_buf: [256][]const u8 = undefined;
    const from_parts = splitPath(from_dir, &from_buf);
    const to_parts = splitPath(to, &to_buf);

    var common: usize = 0;
    while (common < from_parts.len and common < to_parts.len and
        std.mem.eql(u8, from_parts[common], to_parts[common]))
    {
        common += 1;
    }

    const ups = from_parts.len - common;
    const remaining = to_parts[common..];

    var result = std.ArrayListUnmanaged(u8).empty;
    if (ups > 0) {
        for (0..ups) |_| try result.appendSlice(alloc, "../");
    } else {
        try result.appendSlice(alloc, "./");
    }

    for (remaining, 0..) |part, i| {
        try result.appendSlice(alloc, part);
        if (i + 1 < remaining.len) try result.append(alloc, '/');
    }

    return result.toOwnedSlice(alloc);
}

fn splitPath(path: []const u8, buf: [][]const u8) [][]const u8 {
    var count: usize = 0;
    var it = std.mem.splitScalar(u8, path, '/');
    while (it.next()) |part| {
        if (part.len == 0) continue;
        if (count >= buf.len) break;
        buf[count] = part;
        count += 1;
    }
    return buf[0..count];
}

fn resolveExports(exports_val: std.json.Value, pkg_dir: []const u8, src_file: []const u8, io: std.Io, alloc: std.mem.Allocator) !?[]const u8 {
    if (exports_val == .string) {
        const exp_path = try std.fs.path.join(alloc, &.{ pkg_dir, exports_val.string });
        defer alloc.free(exp_path);
        if (try pathExists(exp_path, io)) {
            return try makeRelativeToSrcFile(try std.fmt.allocPrint(alloc, "./{s}", .{exp_path}), src_file, alloc);
        }
    }
    if (exports_val == .object) {
        // Try "." key first (main entry)
        if (exports_val.object.get(".")) |dot| {
            if (dot == .string) {
                const exp_path = try std.fs.path.join(alloc, &.{ pkg_dir, dot.string });
                defer alloc.free(exp_path);
                if (try pathExists(exp_path, io)) {
                    return try makeRelativeToSrcFile(try std.fmt.allocPrint(alloc, "./{s}", .{exp_path}), src_file, alloc);
                }
            }
            if (dot == .object) {
                // Conditional exports: prefer "import", fallback to "default"
                for ([_][]const u8{ "import", "default", "require" }) |cond| {
                    if (dot.object.get(cond)) |cval| {
                        if (cval == .string) {
                            const exp_path = try std.fs.path.join(alloc, &.{ pkg_dir, cval.string });
                            defer alloc.free(exp_path);
                            if (try pathExists(exp_path, io)) {
                                return try makeRelativeToSrcFile(try std.fmt.allocPrint(alloc, "./{s}", .{exp_path}), src_file, alloc);
                            }
                        }
                    }
                }
            }
        }
        // Try direct string values for conditions
        for ([_][]const u8{ "import", "default", "require" }) |cond| {
            if (exports_val.object.get(cond)) |cval| {
                if (cval == .string) {
                    const exp_path = try std.fs.path.join(alloc, &.{ pkg_dir, cval.string });
                    defer alloc.free(exp_path);
                    if (try pathExists(exp_path, io)) {
                        return try makeRelativeToSrcFile(try std.fmt.allocPrint(alloc, "./{s}", .{exp_path}), src_file, alloc);
                    }
                }
            }
        }
    }
    return null;
}

fn resolveNodeModules(pkg: []const u8, src_file: []const u8, io: std.Io, alloc: std.mem.Allocator) !?[]const u8 {
    var search_dir = if (src_file.len > 0) alloc.dupe(u8, std.fs.path.dirname(src_file) orelse ".") catch return null else try alloc.dupe(u8, ".");
    defer alloc.free(search_dir);

    while (true) {
        const nm_dir = try std.fs.path.join(alloc, &.{ search_dir, "node_modules" });
        defer alloc.free(nm_dir);
        const pkg_dir = try std.fs.path.join(alloc, &.{ nm_dir, pkg });
        defer alloc.free(pkg_dir);

        if (try pathExists(pkg_dir, io)) {
            // Try package.json main/exports
            const pkg_json = try std.fs.path.join(alloc, &.{ pkg_dir, "package.json" });
            defer alloc.free(pkg_json);
            const content = std.Io.Dir.cwd().readFileAlloc(io, pkg_json, alloc, std.Io.Limit.limited(16 * 1024)) catch null;
            if (content) |raw| {
                defer alloc.free(raw);
                const parsed = std.json.parseFromSlice(std.json.Value, alloc, raw, .{
                    .ignore_unknown_fields = true,
                    .duplicate_field_behavior = .use_last,
                }) catch return null;
                defer parsed.deinit();

                if (parsed.value == .object) {
                    // Check exports field first (modern packages)
                    if (parsed.value.object.get("exports")) |exports| {
                        if (try resolveExports(exports, pkg_dir, src_file, io, alloc)) |resolved| {
                            return resolved;
                        }
                    }
                    if (parsed.value.object.get("main")) |main| {
                        if (main == .string) {
                            const main_path = try std.fs.path.join(alloc, &.{ pkg_dir, main.string });
                            defer alloc.free(main_path);
                            if (try pathExists(main_path, io)) {
                                return try makeRelativeToSrcFile(try std.fmt.allocPrint(alloc, "./{s}", .{main_path}), src_file, alloc);
                            }
                        }
                    }
                    if (parsed.value.object.get("module")) |mod| {
                        if (mod == .string) {
                            const mod_path = try std.fs.path.join(alloc, &.{ pkg_dir, mod.string });
                            defer alloc.free(mod_path);
                            if (try pathExists(mod_path, io)) {
                                return try makeRelativeToSrcFile(try std.fmt.allocPrint(alloc, "./{s}", .{mod_path}), src_file, alloc);
                            }
                        }
                    }
                }
            }

            // Try index.js, index.mjs
            for ([_][]const u8{ "/index.js", "/index.mjs", "/index.ts" }) |index_file| {
                const indexPath = try std.fmt.allocPrint(alloc, "{s}{s}", .{ pkg_dir, index_file });
                defer alloc.free(indexPath);
                if (try pathExists(indexPath, io)) {
                    return try makeRelativeToSrcFile(try std.fmt.allocPrint(alloc, "./{s}", .{indexPath}), src_file, alloc);
                }
            }
        }

        // Go up one directory
        const parent = std.fs.path.dirname(search_dir) orelse break;
        if (parent.len >= search_dir.len) break;
        const new_dir = try alloc.dupe(u8, parent);
        alloc.free(search_dir);
        search_dir = new_dir;
    }

    return null;
}
