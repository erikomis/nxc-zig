const std = @import("std");
const linter = @import("linter");
const common = @import("common");

const CACHE_VERSION = "1";

pub const CachedFile = struct {
    mtime_ms: f64,
    size: u64,
    diagnostics: []linter.Diagnostic,
};

pub const Cache = struct {
    alloc: std.mem.Allocator,
    io: std.Io,
    config_hash: u64,
    files: std.StringHashMap(CachedFile),
    path: []u8,
    dirty: bool,
    enabled: bool,
    hit_count: usize,
    miss_count: usize,

    pub fn init(alloc: std.mem.Allocator, io: std.Io, cache_path: []const u8, config_hash: u64) Cache {
        return Cache{
            .alloc = alloc,
            .io = io,
            .config_hash = config_hash,
            .files = std.StringHashMap(CachedFile).init(alloc),
            .path = alloc.dupe(u8, cache_path) catch "",
            .dirty = false,
            .enabled = true,
            .hit_count = 0,
            .miss_count = 0,
        };
    }

    pub fn deinit(self: *Cache) void {
        var it = self.files.iterator();
        while (it.next()) |entry| {
            self.alloc.free(entry.key_ptr.*);
            for (entry.value_ptr.diagnostics) |d| freeDiag(self.alloc, d);
            self.alloc.free(entry.value_ptr.diagnostics);
        }
        self.files.deinit();
        if (self.path.len > 0) self.alloc.free(self.path);
    }

    pub fn load(alloc: std.mem.Allocator, io: std.Io, path: []const u8, config_hash: u64) ?Cache {
        const file = std.Io.Dir.cwd().readFileAlloc(io, path, alloc, std.Io.Limit.limited(64 * 1024 * 1024)) catch return null;
        defer alloc.free(file);

        const parsed = std.json.parseFromSlice(std.json.Value, alloc, file, .{
            .ignore_unknown_fields = true,
            .duplicate_field_behavior = .use_last,
        }) catch return null;
        defer parsed.deinit();

        const root = parsed.value;
        if (root != .object) return null;

        const version = root.object.get("version") orelse return null;
        if (version != .string) return null;
        if (!std.mem.eql(u8, version.string, CACHE_VERSION)) return null;

        const stored_hash = root.object.get("configHash") orelse return null;
        const hash_val: u64 = if (stored_hash == .integer)
            @intCast(stored_hash.integer)
        else if (stored_hash == .string)
            std.fmt.parseInt(u64, stored_hash.string, 10) catch return null
        else
            return null;
        if (hash_val != config_hash) return null;

        var cache = Cache.init(alloc, io, path, config_hash);
        errdefer cache.deinit();

        const files_val = root.object.get("files") orelse return null;
        if (files_val != .object) return null;

        var file_it = files_val.object.iterator();
        while (file_it.next()) |entry| {
            const rel_path = entry.key_ptr.*;
            const fe = entry.value_ptr.*;
            if (fe != .object) continue;

            const mtime = fe.object.get("mtimeMs") orelse continue;
            if (mtime != .float) continue;

            const size = fe.object.get("size") orelse continue;
            if (size != .integer) continue;

            const diags_val = fe.object.get("diagnostics") orelse continue;
            if (diags_val != .array) continue;

            const diagnostics = parseDiagnosticsFromJson(diags_val.array, alloc) catch continue;

            const key = alloc.dupe(u8, rel_path) catch {
                for (diagnostics) |d| freeDiag(alloc, d);
                alloc.free(diagnostics);
                continue;
            };
            cache.files.put(key, .{
                .mtime_ms = mtime.float,
                .size = @intCast(size.integer),
                .diagnostics = diagnostics,
            }) catch {
                alloc.free(key);
                for (diagnostics) |d| freeDiag(alloc, d);
                alloc.free(diagnostics);
            };
        }

        return cache;
    }

    pub fn save(self: *Cache) !void {
        if (!self.dirty) return;

        var buf: std.ArrayListUnmanaged(u8) = .empty;
        defer buf.deinit(self.alloc);
        try self.writeJson(&buf);

        const dir = std.fs.path.dirname(self.path) orelse ".";
        std.Io.Dir.cwd().createDirPath(self.io, dir) catch {};

        std.Io.Dir.cwd().writeFile(self.io, .{
            .sub_path = self.path,
            .data = buf.items,
        }) catch {};

        self.dirty = false;
    }

    fn writeJson(self: *Cache, buf: *std.ArrayListUnmanaged(u8)) !void {
        const alloc = self.alloc;
        try buf.appendSlice(alloc, "{\n");
        try buf.print(alloc, "\"version\": \"{s}\",\n", .{CACHE_VERSION});
        try buf.print(alloc, "\"configHash\": \"{d}\",\n", .{self.config_hash});
        try buf.appendSlice(alloc, "\"files\": {\n");

        var it = self.files.iterator();
        var first = true;
        while (it.next()) |entry| {
            if (!first) try buf.appendSlice(alloc, ",\n");
            first = false;

            const rel_path = entry.key_ptr.*;
            const file = entry.value_ptr.*;

            try buf.appendSlice(alloc, "  ");
            try appendJsonStr(buf, alloc, rel_path);
            try buf.appendSlice(alloc, ": {\n");

            try buf.print(alloc, "    \"mtimeMs\": {d},\n", .{file.mtime_ms});
            try buf.print(alloc, "    \"size\": {d},\n", .{file.size});
            try buf.appendSlice(alloc, "    \"diagnostics\": [\n");

            for (file.diagnostics, 0..) |diag, i| {
                if (i > 0) try buf.appendSlice(alloc, ",\n");
                try buf.appendSlice(alloc, "      {\n");
                try buf.appendSlice(alloc, "        \"message\": ");
                try appendJsonStr(buf, alloc, diag.message);
                try buf.appendSlice(alloc, ",\n");
                try buf.print(alloc, "        \"severity\": \"{s}\",\n", .{severityStr(diag.severity)});
                try buf.appendSlice(alloc, "        \"filename\": ");
                try appendJsonStr(buf, alloc, diag.filename);
                try buf.appendSlice(alloc, ",\n");
                try buf.appendSlice(alloc, "        \"ruleCode\": ");
                try appendJsonStr(buf, alloc, diag.rule_code);
                try buf.appendSlice(alloc, ",\n");
                try buf.appendSlice(alloc, "        \"range\": {\n");
                try buf.print(alloc, "          \"start\": {{\"index\": {}, \"line\": {}, \"column\": {}}},\n", .{
                    diag.range.start.index, diag.range.start.line, diag.range.start.column,
                });
                try buf.print(alloc, "          \"end\": {{\"index\": {}, \"line\": {}, \"column\": {}}}\n", .{
                    diag.range.end.index, diag.range.end.line, diag.range.end.column,
                });
                try buf.appendSlice(alloc, "        }\n");
                try buf.appendSlice(alloc, "      }");
            }

            try buf.appendSlice(alloc, "\n    ]\n  }");
        }

        try buf.appendSlice(alloc, "\n}\n}\n");
    }

    pub fn shouldLint(self: *Cache, rel_path: []const u8, mtime_ms: f64, size: u64) bool {
        if (!self.enabled) return true;

        if (self.files.get(rel_path)) |cached| {
            if (cached.mtime_ms == mtime_ms and cached.size == size) {
                self.hit_count += 1;
                return false;
            }
        }

        self.miss_count += 1;
        return true;
    }

    pub fn getCachedDiagnostics(self: *Cache, rel_path: []const u8) ?[]const linter.Diagnostic {
        if (self.files.get(rel_path)) |cached| {
            return cached.diagnostics;
        }
        return null;
    }

    pub fn update(self: *Cache, rel_path: []const u8, mtime_ms: f64, size: u64, diagnostics: []const linter.Diagnostic) !void {
        if (!self.enabled) return;

        if (self.files.fetchRemove(rel_path)) |old| {
            self.alloc.free(old.key);
            for (old.value.diagnostics) |d| freeDiag(self.alloc, d);
            self.alloc.free(old.value.diagnostics);
        }

        var diags_copy = try self.alloc.alloc(linter.Diagnostic, diagnostics.len);
        errdefer self.alloc.free(diags_copy);
        for (diagnostics, 0..) |d, i| {
            diags_copy[i] = try cloneDiag(self.alloc, d);
        }

        const key = try self.alloc.dupe(u8, rel_path);
        self.files.put(key, .{
            .mtime_ms = mtime_ms,
            .size = size,
            .diagnostics = diags_copy,
        }) catch {
            self.alloc.free(key);
            for (diags_copy) |d| freeDiag(self.alloc, d);
            self.alloc.free(diags_copy);
        };
        self.dirty = true;
    }

    pub fn removeMissing(self: *Cache, valid_paths: []const []const u8) void {
        var valid = std.StringHashMap(void).init(self.alloc);
        defer valid.deinit();
        for (valid_paths) |p| {
            valid.put(p, {}) catch {};
        }

        var to_remove = std.ArrayListUnmanaged([]const u8).empty;
        defer {
            for (to_remove.items) |k| self.alloc.free(k);
            to_remove.deinit(self.alloc);
        }

        var it = self.files.iterator();
        while (it.next()) |entry| {
            if (!valid.contains(entry.key_ptr.*)) {
                to_remove.append(self.alloc, entry.key_ptr.*) catch {};
            }
        }

        for (to_remove.items) |key| {
            if (self.files.fetchRemove(key)) |removed| {
                self.alloc.free(removed.key);
                for (removed.value.diagnostics) |d| freeDiag(self.alloc, d);
                self.alloc.free(removed.value.diagnostics);
                self.dirty = true;
            }
        }
    }

    pub fn logStats(self: *const Cache) void {
        if (self.enabled) {
            std.debug.print("[cache] hits: {d}, misses: {d}\n", .{ self.hit_count, self.miss_count });
        }
    }
};

pub fn normalizePath(path: []const u8, root: []const u8, alloc: std.mem.Allocator) ![]u8 {
    const rel = if (std.mem.startsWith(u8, path, root)) rel: {
        var r = path[root.len..];
        if (r.len > 0 and (r[0] == '/' or r[0] == '\\')) r = r[1..];
        break :rel r;
    } else path;

    var result = try alloc.alloc(u8, rel.len);
    for (rel, 0..) |c, i| {
        result[i] = if (c == '\\') '/' else c;
    }
    return result;
}

pub fn findProjectRoot(io: std.Io, alloc: std.mem.Allocator) []const u8 {
    const cwd = std.process.currentPathAlloc(io, alloc) catch return alloc.dupe(u8, ".") catch ".";
    defer alloc.free(cwd);

    const config_filenames = [_][]const u8{ "nxc.config.js", "nxc.json", ".nxrc", ".nxrc.json" };

    var dir = alloc.dupe(u8, cwd) catch return alloc.dupe(u8, ".") catch ".";
    defer alloc.free(dir);

    while (true) {
        for (config_filenames) |name| {
            const path = std.fs.path.join(alloc, &.{ dir, name }) catch continue;
            defer alloc.free(path);
            const stat = std.Io.Dir.cwd().statFile(io, path, .{}) catch continue;
            if (stat.kind == .file) return alloc.dupe(u8, dir) catch ".";
        }

        const parent = std.fs.path.dirname(dir) orelse break;
        if (parent.len >= dir.len) break;
        const new_dir = alloc.dupe(u8, parent) catch break;
        alloc.free(dir);
        dir = new_dir;
    }

    return alloc.dupe(u8, ".") catch ".";
}

pub fn computeConfigHash(cfg: linter.Config, alloc: std.mem.Allocator) u64 {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(alloc);

    buf.print(alloc, "env:{any};", .{cfg.env}) catch return 0;
    buf.appendSlice(alloc, "rules:[") catch return 0;
    for (cfg.rule_overrides.items, 0..) |r, i| {
        if (i > 0) buf.appendSlice(alloc, ",") catch return 0;
        buf.print(alloc, "{s}:{any}:{any}", .{ r.code, r.enabled, r.severity }) catch return 0;
    }
    buf.appendSlice(alloc, "];") catch return 0;

    var hasher = std.hash.XxHash64.init(0);
    hasher.update(buf.items);
    return hasher.final();
}

pub fn defaultCachePath(io: std.Io, alloc: std.mem.Allocator) ![]u8 {
    const root = findProjectRoot(io, alloc);
    defer alloc.free(root);
    return std.fs.path.join(alloc, &.{ root, "node_modules", "nxc", ".cache", "linter.json" });
}

fn appendJsonStr(buf: *std.ArrayListUnmanaged(u8), alloc: std.mem.Allocator, s: []const u8) !void {
    try buf.append(alloc, '"');
    for (s) |c| {
        switch (c) {
            '"' => try buf.appendSlice(alloc, "\\\""),
            '\\' => try buf.appendSlice(alloc, "\\\\"),
            '\n' => try buf.appendSlice(alloc, "\\n"),
            '\r' => try buf.appendSlice(alloc, "\\r"),
            '\t' => try buf.appendSlice(alloc, "\\t"),
            else => try buf.append(alloc, c),
        }
    }
    try buf.append(alloc, '"');
}

fn parseDiagnosticsFromJson(arr: std.json.Array, alloc: std.mem.Allocator) ![]linter.Diagnostic {
    var result = try alloc.alloc(linter.Diagnostic, arr.items.len);
    var count: usize = 0;
    errdefer {
        for (0..count) |i| freeDiag(alloc, result[i]);
        alloc.free(result);
    }

    for (arr.items, 0..) |item, i| {
        if (item != .object) return error.InvalidCache;
        const obj = item.object;

        const message = obj.get("message") orelse return error.InvalidCache;
        if (message != .string) return error.InvalidCache;

        const severity = obj.get("severity") orelse return error.InvalidCache;
        if (severity != .string) return error.InvalidCache;

        const filename = obj.get("filename") orelse return error.InvalidCache;
        if (filename != .string) return error.InvalidCache;

        const rule_code = obj.get("ruleCode") orelse return error.InvalidCache;
        if (rule_code != .string) return error.InvalidCache;

        const range_val = obj.get("range") orelse return error.InvalidCache;
        if (range_val != .object) return error.InvalidCache;

        const start_val = range_val.object.get("start") orelse return error.InvalidCache;
        const end_val = range_val.object.get("end") orelse return error.InvalidCache;
        if (start_val != .object or end_val != .object) return error.InvalidCache;

        const sev: common.Severity = if (std.mem.eql(u8, severity.string, "warn"))
            .warn
        else if (std.mem.eql(u8, severity.string, "info"))
            .info
        else
            .err;

        result[i] = linter.Diagnostic{
            .message = try alloc.dupe(u8, message.string),
            .severity = sev,
            .filename = try alloc.dupe(u8, filename.string),
            .rule_code = try alloc.dupe(u8, rule_code.string),
            .range = .{
                .start = .{
                    .index = jsonInt(start_val, "index"),
                    .line = @intCast(jsonInt(start_val, "line")),
                    .column = @intCast(jsonInt(start_val, "column")),
                },
                .end = .{
                    .index = jsonInt(end_val, "index"),
                    .line = @intCast(jsonInt(end_val, "line")),
                    .column = @intCast(jsonInt(end_val, "column")),
                },
            },
        };
        count = i + 1;
    }

    return result;
}

fn jsonInt(val: std.json.Value, key: []const u8) usize {
    if (val != .object) return 0;
    const field = val.object.get(key) orelse return 0;
    return if (field == .integer) @intCast(field.integer) else 0;
}

fn severityStr(severity: common.Severity) []const u8 {
    return switch (severity) {
        .off => "off",
        .err => "err",
        .warn => "warn",
        .info => "info",
    };
}

fn freeDiag(alloc: std.mem.Allocator, d: linter.Diagnostic) void {
    alloc.free(d.message);
    alloc.free(d.filename);
    alloc.free(d.rule_code);
}

fn cloneDiag(alloc: std.mem.Allocator, d: linter.Diagnostic) !linter.Diagnostic {
    return linter.Diagnostic{
        .message = try alloc.dupe(u8, d.message),
        .severity = d.severity,
        .filename = try alloc.dupe(u8, d.filename),
        .rule_code = try alloc.dupe(u8, d.rule_code),
        .range = d.range,
    };
}
