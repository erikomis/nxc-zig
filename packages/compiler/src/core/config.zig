const std = @import("std");
const Io = std.Io;

const jsx = @import("jsx");
const modules = @import("modules");
const aliases = @import("aliases");
const json5 = @import("json5");

pub const Target = enum { es2020, es2022, es2024, esnext };
pub const PathAlias = aliases.PathAlias;
pub const ParserSyntax = enum { typescript, ecmascript };

pub const ParserConfig = struct {
    syntax: ParserSyntax = .typescript,
    decorators: bool = true,
};

pub const ReactTransformConfig = struct {
    jsx_runtime: jsx.JsxRuntime = .classic,
    jsx_factory: []const u8 = "React.createElement",
    jsx_fragment: []const u8 = "React.Fragment",
    jsx_import_source: []const u8 = "react",
};

pub const TransformConfig = struct {
    decorator_metadata: bool = true,
    legacy_decorator: bool = true,
    react: ReactTransformConfig = .{},
};

pub const ModuleConfig = struct {
    strict: bool = true,
    target: modules.ModuleTarget = .esm,
    es_module_interop: bool = true,
    import_interop: modules.ImportInterop = .node,
    resolve_full_paths: bool = true,
};

pub const Config = struct {
    base_url: ?[]const u8 = null,
    parser: ParserConfig = .{},
    jsx: bool = true,
    check: bool = true,
    module: ModuleConfig = .{},
    source_maps: bool = true,
    declaration: bool = true,
    target: Target = .es2024,
    transform: TransformConfig = .{},
    keep_class_names: bool = true,
    keep_import_attributes: bool = true,
    remove_comments: bool = true,
    paths: []const PathAlias = &.{},
};

pub const TsCompilerOptions = struct {
    base_url: ?[]const u8 = null,
    target: ?[]const u8 = null,
    jsx: ?[]const u8 = null,
    jsx_import_source: ?[]const u8 = null,
    strict: ?bool = null,
    experimental_decorators: ?bool = null,
    esmodule_interop: ?bool = null,
    source_maps: ?bool = null,
    declaration: ?bool = null,
    paths: []PathAlias = &.{},
};

pub const TsConfig = struct {
    compiler_options: TsCompilerOptions = .{},
};

pub fn readTsConfig(path: []const u8, io: Io, alloc: std.mem.Allocator) !?TsConfig {
    const content = Io.Dir.cwd().readFileAlloc(
        io,
        path,
        alloc,
        Io.Limit.limited(1024 * 1024),
    ) catch |err| {
        if (err == error.FileNotFound) return null;
        if (err == error.StreamTooLong) return error.FileTooLarge;
        return err;
    };
    defer alloc.free(content);

    const parsed = json5.parse(content, alloc) catch return null;
    defer parsed.deinit();

    const root = parsed.value;
    if (root != .object) return null;

    var cfg = TsConfig{};

    // compilerOptions
    if (root.object.get("compilerOptions")) |co| {
        if (co == .object) {
            cfg.compiler_options = try parseCompilerOptions(co.object, alloc);
        }
    }

    return cfg;
}

fn parseCompilerOptions(obj: std.json.ObjectMap, alloc: std.mem.Allocator) !TsCompilerOptions {
    var co = TsCompilerOptions{};

    if (obj.get("target")) |v| {
        if (v == .string) co.target = try alloc.dupe(u8, v.string);
    }
    if (obj.get("jsx")) |v| {
        if (v == .string) co.jsx = try alloc.dupe(u8, v.string);
    }
    if (obj.get("jsxImportSource")) |v| {
        if (v == .string) co.jsx_import_source = try alloc.dupe(u8, v.string);
    }
    if (obj.get("baseUrl")) |v| {
        if (v == .string) co.base_url = try alloc.dupe(u8, v.string);
    }
    if (obj.get("strict")) |v| {
        if (v == .bool) co.strict = v.bool;
    }
    if (obj.get("esModuleInterop")) |v| {
        if (v == .bool) co.esmodule_interop = v.bool;
    }
    if (obj.get("declaration")) |v| {
        if (v == .bool) co.declaration = v.bool;
    }
    if (obj.get("sourceMap")) |v| {
        if (v == .bool) co.source_maps = v.bool;
    }
    if (obj.get("experimentalDecorators")) |v| {
        if (v == .bool) co.experimental_decorators = v.bool;
    }
    if (obj.get("paths")) |v| {
        if (v == .object) {
            co.paths = try parsePaths(v.object, alloc);
        }
    }

    return co;
}

pub fn parseSupportedTarget(raw: []const u8) !Target {
    if (std.ascii.eqlIgnoreCase(raw, "es2020")) return .es2020;
    if (std.ascii.eqlIgnoreCase(raw, "es2022")) return .es2022;
    if (std.ascii.eqlIgnoreCase(raw, "es2024")) return .es2024;
    if (std.ascii.eqlIgnoreCase(raw, "esnext")) return .esnext;
    return error.UnsupportedTsTarget;
}

pub fn applyCompilerOptions(opts: TsCompilerOptions, cfg: *Config) !void {
    if (opts.target) |t| cfg.*.target = try parseSupportedTarget(t);
    if (opts.jsx) |j| {
        if (!std.ascii.eqlIgnoreCase(j, "preserve")) cfg.*.jsx = true;
        if (std.mem.eql(u8, j, "react-jsx") or std.mem.eql(u8, j, "react-jsxdev")) cfg.*.transform.react.jsx_runtime = .automatic;
    }
    if (opts.jsx_import_source) |src| cfg.*.transform.react.jsx_import_source = src;
    if (opts.experimental_decorators) |enabled| cfg.*.parser.decorators = enabled;
    if (opts.esmodule_interop) |enabled| cfg.*.module.es_module_interop = enabled;
    if (opts.source_maps) |enabled| cfg.*.source_maps = enabled;
    if (opts.declaration) |enabled| cfg.*.declaration = enabled;
    if (opts.paths.len > 0) cfg.*.paths = opts.paths;
    if (opts.base_url) |bu| cfg.*.base_url = bu;
    if (opts.strict) |strict| cfg.*.module.strict = strict;
}



fn parsePaths(obj: std.json.ObjectMap, alloc: std.mem.Allocator) ![]PathAlias {
    var result = std.ArrayListUnmanaged(PathAlias).empty;
    errdefer {
        for (result.items) |a| {
            alloc.free(a.prefix);
            alloc.free(a.replacement);
        }
        result.deinit(alloc);
    }

    var it = obj.iterator();
    while (it.next()) |entry| {
        const key = entry.key_ptr.*;
        const val = entry.value_ptr.*;
        if (val != .array or val.array.items.len == 0) continue;
        const first = val.array.items[0];
        if (first != .string) continue;

        // Wildcard: key ends with "/*" → strip the trailing "*", keep "prefix/"
        // Exact: no wildcard → match full path only
        const is_wildcard = std.mem.endsWith(u8, key, "/*");
        const prefix_raw = if (is_wildcard) key[0 .. key.len - 1] else key;
        const repl_raw = if (std.mem.endsWith(u8, first.string, "/*")) first.string[0 .. first.string.len - 1] else first.string;

        try result.append(alloc, .{
            .prefix = try alloc.dupe(u8, prefix_raw),
            .replacement = try alloc.dupe(u8, repl_raw),
            .is_wildcard = is_wildcard,
        });
    }

    return result.toOwnedSlice(alloc);
}
