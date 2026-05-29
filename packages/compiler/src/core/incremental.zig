const std = @import("std");
const cache = @import("cache");
const compiler = @import("compiler");
const config = @import("config");
const diagnostics = @import("diagnostics");
const parser_mod = @import("parser");
const ast_mod = @import("ast");

const CacheEntry = cache.CacheEntry;
const CacheStore = cache.CacheStore;
const Config = config.Config;
const CompileResult = compiler.CompileResult;
const Diagnostic = diagnostics.Diagnostic;

pub const IncrementalCompiler = struct {
    cache: CacheStore,
    config: Config,

    pub fn init(cache_dir: []const u8, cfg: Config) IncrementalCompiler {
        return .{
            .cache = CacheStore.init(cache_dir),
            .config = cfg,
        };
    }

    pub fn compileFile(
        self: *IncrementalCompiler,
        path: []const u8,
        io: std.Io,
        alloc: std.mem.Allocator,
    ) !CompileResult {
        const source = std.Io.Dir.cwd().readFileAlloc(io, path, alloc, std.Io.Limit.limited(64 * 1024 * 1024)) catch |err| switch (err) {
            error.StreamTooLong => return error.FileTooLarge,
            else => return err,
        };
        defer alloc.free(source);

        var hasher = std.hash.Wyhash.init(0);
        hasher.update(source);
        const source_hash = hasher.final();

        if (self.cache.get(path)) |entry| {
            if (entry.source_hash == source_hash) {
                const result = loadCachedOutput(path, io, alloc) catch {
                    return self.compileAndCache(path, source_hash, io, alloc);
                };
                return result;
            }
        }

        return self.compileAndCache(path, source_hash, io, alloc);
    }

    fn compileAndCache(
        self: *IncrementalCompiler,
        path: []const u8,
        source_hash: u64,
        io: std.Io,
        alloc: std.mem.Allocator,
    ) !CompileResult {
        const result = try compiler.compileFile(path, self.config, io, alloc);

        var out_hasher = std.hash.Wyhash.init(0);
        out_hasher.update(result.code);
        if (result.map) |m| out_hasher.update(m);
        if (result.declarations) |d| out_hasher.update(d);
        const output_hash = out_hasher.final();

        const deps = try extractDeps(path, io, alloc);
        defer {
            for (deps) |d| alloc.free(d);
            alloc.free(deps);
        }

        var dep_hashes = std.ArrayListUnmanaged(u64).empty;
        for (deps) |dep| {
            const dep_hash = cache.hashFile(dep, io, alloc) catch continue;
            try dep_hashes.append(alloc, dep_hash);
        }

        var deps_joined = std.ArrayListUnmanaged(u8).empty;
        for (deps, 0..) |dep, i| {
            if (i > 0) try deps_joined.append(alloc, ',');
            try deps_joined.appendSlice(alloc, dep);
        }

        const ts = std.Io.Timestamp.now(io, .real);
        const entry = CacheEntry{
            .source_hash = source_hash,
            .deps = try deps_joined.toOwnedSlice(alloc),
            .dep_hashes = try dep_hashes.toOwnedSlice(alloc),
            .output_hash = output_hash,
            .last_modified = ts.nanoseconds,
            .source_path = try alloc.dupe(u8, path),
        };
        try self.cache.put(alloc, path, entry);

        return result;
    }

    pub fn isStaleCheck(self: *IncrementalCompiler, path: []const u8, current_hash: u64, io: std.Io, alloc: std.mem.Allocator) bool {
        if (self.cache.isStale(path, current_hash)) return true;
        const entry = self.cache.get(path) orelse return true;
        for (entry.dep_hashes, 0..) |cached_hash, i| {
            var it = std.mem.splitScalar(u8, entry.deps, ',');
            var j: usize = 0;
            while (it.next()) |dep_path| : (j += 1) {
                if (j != i) continue;
                if (dep_path.len == 0) continue;
                const current_dep_hash = cache.hashFile(dep_path, io, alloc) catch return true;
                if (current_dep_hash != cached_hash) return true;
                break;
            }
        }
        return false;
    }

    pub fn deinit(self: *IncrementalCompiler, io: std.Io, alloc: std.mem.Allocator) void {
        self.cache.save(io, alloc) catch |err| {
            std.log.err("incremental: failed to save cache: {}", .{err});
        };
        self.cache.deinit(alloc);
    }

    pub fn load(self: *IncrementalCompiler, io: std.Io, alloc: std.mem.Allocator) !void {
        try self.cache.load(io, alloc);
    }

    pub fn save(self: *IncrementalCompiler, io: std.Io, alloc: std.mem.Allocator) !void {
        try self.cache.save(io, alloc);
    }
};

fn loadCachedOutput(path: []const u8, io: std.Io, alloc: std.mem.Allocator) !CompileResult {
    const js_path = try jsPathFromSourcePath(path, alloc);
    defer alloc.free(js_path);

    const code = std.Io.Dir.cwd().readFileAlloc(io, js_path, alloc, std.Io.Limit.limited(64 * 1024 * 1024)) catch |err| switch (err) {
        error.StreamTooLong => return error.FileTooLarge,
        else => return err,
    };

    const map_path = try std.fmt.allocPrint(alloc, "{s}.map", .{js_path});
    defer alloc.free(map_path);
    const map = std.Io.Dir.cwd().readFileAlloc(io, map_path, alloc, std.Io.Limit.limited(64 * 1024 * 1024)) catch null;

    const decl_path = try compiler.declarationPathFromJsPath(alloc, js_path);
    defer alloc.free(decl_path);
    const declarations = std.Io.Dir.cwd().readFileAlloc(io, decl_path, alloc, std.Io.Limit.limited(64 * 1024 * 1024)) catch null;

    return CompileResult{
        .code = code,
        .map = map,
        .declarations = declarations,
        .diagnostics = try alloc.dupe(Diagnostic, &.{}),
    };
}

fn jsPathFromSourcePath(path: []const u8, alloc: std.mem.Allocator) ![]u8 {
    if (std.mem.endsWith(u8, path, ".ts")) {
        return std.fmt.allocPrint(alloc, "{s}.js", .{path[0 .. path.len - 3]});
    }
    if (std.mem.endsWith(u8, path, ".tsx")) {
        return std.fmt.allocPrint(alloc, "{s}.js", .{path[0 .. path.len - 4]});
    }
    if (std.mem.endsWith(u8, path, ".mts")) {
        return std.fmt.allocPrint(alloc, "{s}.mjs", .{path[0 .. path.len - 4]});
    }
    if (std.mem.endsWith(u8, path, ".cts")) {
        return std.fmt.allocPrint(alloc, "{s}.cjs", .{path[0 .. path.len - 4]});
    }
    return std.fmt.allocPrint(alloc, "{s}.js", .{path});
}

fn extractDeps(path: []const u8, io: std.Io, alloc: std.mem.Allocator) ![][]const u8 {
    const source = std.Io.Dir.cwd().readFileAlloc(io, path, alloc, std.Io.Limit.limited(10 * 1024 * 1024)) catch return &.{};
    defer alloc.free(source);

    var arena_backing = std.heap.ArenaAllocator.init(alloc);
    defer arena_backing.deinit();
    const a = arena_backing.allocator();

    var diags = diagnostics.DiagnosticList{};
    var node_arena = ast_mod.Arena.init(a);
    var p = parser_mod.Parser.init(source, path, &node_arena, a, &diags, .{ .check = false });

    const program_id = p.parseProgram() catch return &.{};
    _ = program_id;

    var result = std.ArrayListUnmanaged([]const u8).empty;
    const dir = std.fs.path.dirname(path) orelse ".";

    for (node_arena.nodes.items) |node| {
        if (node == .import_decl) {
            const src = node.import_decl.source;
            const src_node = node_arena.get(src);
            if (src_node.* == .str_lit) {
                const import_path = src_node.str_lit.value;
                if (!std.mem.startsWith(u8, import_path, ".") and !std.mem.startsWith(u8, import_path, "/")) continue;
                const resolved = std.fs.path.join(alloc, &.{ dir, import_path }) catch continue;
                const with_ext = try resolveTsExt(resolved, io, alloc);
                try result.append(alloc, with_ext);
            }
        }
        if (node == .export_decl) {
            const exp = node.export_decl;
            switch (exp.kind) {
                .named => |n| {
                    if (n.source) |src_id| {
                        const src_node = node_arena.get(src_id);
                        if (src_node.* == .str_lit) {
                            const exp_path = src_node.str_lit.value;
                            if (!std.mem.startsWith(u8, exp_path, ".") and !std.mem.startsWith(u8, exp_path, "/")) continue;
                            const resolved = std.fs.path.join(alloc, &.{ dir, exp_path }) catch continue;
                            const with_ext = try resolveTsExt(resolved, io, alloc);
                            try result.append(alloc, with_ext);
                        }
                    }
                },
                .all => |all_exp| {
                    const src_node = node_arena.get(all_exp.source);
                    if (src_node.* == .str_lit) {
                        const exp_path = src_node.str_lit.value;
                        if (!std.mem.startsWith(u8, exp_path, ".") and !std.mem.startsWith(u8, exp_path, "/")) continue;
                        const resolved = std.fs.path.join(alloc, &.{ dir, exp_path }) catch continue;
                        const with_ext = try resolveTsExt(resolved, io, alloc);
                        try result.append(alloc, with_ext);
                    }
                },
                else => {},
            }
        }
    }

    return result.toOwnedSlice(alloc);
}

fn resolveTsExt(path: []const u8, io: std.Io, alloc: std.mem.Allocator) ![]u8 {
    const extensions = [_][]const u8{ ".ts", ".tsx", ".mts", ".cts", ".js", ".jsx", "/index.ts", "/index.tsx", "/index.js" };
    for (extensions) |ext| {
        const candidate = try std.fmt.allocPrint(alloc, "{s}{s}", .{ path, ext });
        if (std.Io.Dir.cwd().statFile(io, candidate, .{})) |_| {
            return candidate;
        } else |_| {
            alloc.free(candidate);
        }
    }
    return try alloc.dupe(u8, path);
}
