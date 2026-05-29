const std = @import("std");
const Io = std.Io;

const jsx = @import("jsx");
const modules = @import("modules");
const aliases = @import("aliases");
const json5 = @import("json5");

pub const Target = enum { es2015, es2016, es2017, es2018, es2019, es2020, es2022, es2024, esnext };
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
    minify: bool = false,
<<<<<<< HEAD
    inline_source_map: bool = false,
    inline_sources: bool = false,
    declaration_dir: ?[]const u8 = null,
    no_emit: bool = false,
    emit_declaration_only: bool = false,
    allow_js: bool = false,
=======
>>>>>>> 6e4d7f2 (feat(cli): adicionar suporte à opção --minify)
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
    out_dir: ?[]const u8 = null,
    out_file: ?[]const u8 = null,
    root_dir: ?[]const u8 = null,
    allow_js: ?bool = null,
    check_js: ?bool = null,
    remove_comments: ?bool = null,
    no_emit: ?bool = null,
    resolve_json_module: ?bool = null,
    isolated_modules: ?bool = null,
    declaration_dir: ?[]const u8 = null,
    inline_source_map: ?bool = null,
    inline_sources: ?bool = null,
    emit_declaration_only: ?bool = null,
    module: ?[]const u8 = null,
};

pub const TsConfig = struct {
    compiler_options: TsCompilerOptions = .{},
    extends: ?[]const u8 = null,
    files: [][]const u8 = &.{},
    include: [][]const u8 = &.{},
    exclude: [][]const u8 = &.{},
    references: [][]const u8 = &.{},
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

    // extends
    if (root.object.get("extends")) |ext| {
        if (ext == .string) {
            const base_dir = std.fs.path.dirname(path) orelse ".";
            const base_path = try std.fs.path.join(alloc, &.{ base_dir, ext.string });
            defer alloc.free(base_path);

            if (try readTsConfig(base_path, io, alloc)) |base| {
                mergeOpts(&cfg.compiler_options, base.compiler_options);
            }
        }
    }

    // files
    if (root.object.get("files")) |v| {
        if (v == .array) {
            cfg.files = try parseStringArray(v.array, alloc);
        }
    }

    // include
    if (root.object.get("include")) |v| {
        if (v == .array) {
            cfg.include = try parseStringArray(v.array, alloc);
        }
    }

    // exclude
    if (root.object.get("exclude")) |v| {
        if (v == .array) {
            cfg.exclude = try parseStringArray(v.array, alloc);
        }
    }

    // references: [ { "path": "..." }, ... ]
    if (root.object.get("references")) |v| {
        if (v == .array) {
            var refs = std.ArrayListUnmanaged([]const u8).empty;
            for (v.array.items) |item| {
                if (item == .object) {
                    if (item.object.get("path")) |p| {
                        if (p == .string) {
                            try refs.append(alloc, try alloc.dupe(u8, p.string));
                        }
                    }
                }
            }
            cfg.references = try refs.toOwnedSlice(alloc);
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
    if (obj.get("outDir")) |v| {
        if (v == .string) co.out_dir = try alloc.dupe(u8, v.string);
    }
    if (obj.get("outFile")) |v| {
        if (v == .string) co.out_file = try alloc.dupe(u8, v.string);
    }
    if (obj.get("rootDir")) |v| {
        if (v == .string) co.root_dir = try alloc.dupe(u8, v.string);
    }
    if (obj.get("allowJs")) |v| {
        if (v == .bool) co.allow_js = v.bool;
    }
    if (obj.get("checkJs")) |v| {
        if (v == .bool) co.check_js = v.bool;
    }
    if (obj.get("removeComments")) |v| {
        if (v == .bool) co.remove_comments = v.bool;
    }
    if (obj.get("noEmit")) |v| {
        if (v == .bool) co.no_emit = v.bool;
    }
    if (obj.get("resolveJsonModule")) |v| {
        if (v == .bool) co.resolve_json_module = v.bool;
    }
    if (obj.get("isolatedModules")) |v| {
        if (v == .bool) co.isolated_modules = v.bool;
    }
    if (obj.get("declarationDir")) |v| {
        if (v == .string) co.declaration_dir = try alloc.dupe(u8, v.string);
    }
    if (obj.get("inlineSourceMap")) |v| {
        if (v == .bool) co.inline_source_map = v.bool;
    }
    if (obj.get("inlineSources")) |v| {
        if (v == .bool) co.inline_sources = v.bool;
    }
    if (obj.get("emitDeclarationOnly")) |v| {
        if (v == .bool) co.emit_declaration_only = v.bool;
    }
    if (obj.get("module")) |v| {
        if (v == .string) co.module = try alloc.dupe(u8, v.string);
    }

    return co;
}

pub fn parseSupportedTarget(raw: []const u8) !Target {
    if (std.ascii.eqlIgnoreCase(raw, "es2015") or std.ascii.eqlIgnoreCase(raw, "es6")) return .es2015;
    if (std.ascii.eqlIgnoreCase(raw, "es2016")) return .es2016;
    if (std.ascii.eqlIgnoreCase(raw, "es2017")) return .es2017;
    if (std.ascii.eqlIgnoreCase(raw, "es2018")) return .es2018;
    if (std.ascii.eqlIgnoreCase(raw, "es2019")) return .es2019;
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
    if (opts.remove_comments) |rc| cfg.*.remove_comments = rc;
    if (opts.module) |m| {
        if (std.ascii.eqlIgnoreCase(m, "commonjs") or std.ascii.eqlIgnoreCase(m, "cjs")) {
            cfg.*.module.target = .cjs;
        }
    }
    // outDir, outFile, rootDir, allowJs, checkJs, noEmit, resolveJsonModule,
    // isolatedModules, declarationDir, inlineSourceMap, inlineSources,
    // emitDeclarationOnly, module: parsed but consumed by CLI layer.
}

fn mergeOpts(into: *TsCompilerOptions, base: TsCompilerOptions) void {
    if (base.target != null and into.target == null) into.target = base.target;
    if (base.jsx != null and into.jsx == null) into.jsx = base.jsx;
    if (base.jsx_import_source != null and into.jsx_import_source == null) into.jsx_import_source = base.jsx_import_source;
    if (base.base_url != null and into.base_url == null) into.base_url = base.base_url;
    if (base.strict != null and into.strict == null) into.strict = base.strict;
    if (base.experimental_decorators != null and into.experimental_decorators == null) into.experimental_decorators = base.experimental_decorators;
    if (base.esmodule_interop != null and into.esmodule_interop == null) into.esmodule_interop = base.esmodule_interop;
    if (base.source_maps != null and into.source_maps == null) into.source_maps = base.source_maps;
    if (base.declaration != null and into.declaration == null) into.declaration = base.declaration;
    if (base.paths.len > 0 and into.paths.len == 0) into.paths = base.paths;
    if (base.out_dir != null and into.out_dir == null) into.out_dir = base.out_dir;
    if (base.out_file != null and into.out_file == null) into.out_file = base.out_file;
    if (base.root_dir != null and into.root_dir == null) into.root_dir = base.root_dir;
    if (base.allow_js != null and into.allow_js == null) into.allow_js = base.allow_js;
    if (base.check_js != null and into.check_js == null) into.check_js = base.check_js;
    if (base.remove_comments != null and into.remove_comments == null) into.remove_comments = base.remove_comments;
    if (base.no_emit != null and into.no_emit == null) into.no_emit = base.no_emit;
    if (base.resolve_json_module != null and into.resolve_json_module == null) into.resolve_json_module = base.resolve_json_module;
    if (base.isolated_modules != null and into.isolated_modules == null) into.isolated_modules = base.isolated_modules;
    if (base.declaration_dir != null and into.declaration_dir == null) into.declaration_dir = base.declaration_dir;
    if (base.inline_source_map != null and into.inline_source_map == null) into.inline_source_map = base.inline_source_map;
    if (base.inline_sources != null and into.inline_sources == null) into.inline_sources = base.inline_sources;
    if (base.emit_declaration_only != null and into.emit_declaration_only == null) into.emit_declaration_only = base.emit_declaration_only;
    if (base.module != null and into.module == null) into.module = base.module;
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

fn parseStringArray(arr: std.json.Array, alloc: std.mem.Allocator) ![][]const u8 {
    var result = std.ArrayListUnmanaged([]const u8).empty;
    errdefer {
        for (result.items) |s| alloc.free(s);
        result.deinit(alloc);
    }
    for (arr.items) |item| {
        if (item == .string) {
            try result.append(alloc, try alloc.dupe(u8, item.string));
        }
    }
    return result.toOwnedSlice(alloc);
}

pub fn resolveConfigFiles(cfg: *const TsConfig, base_path: []const u8, io: Io, alloc: std.mem.Allocator) ![][]const u8 {
    var result = std.ArrayListUnmanaged([]const u8).empty;

    if (cfg.files.len > 0) {
        for (cfg.files) |f| {
            const full = try std.fs.path.join(alloc, &.{ base_path, f });
            try result.append(alloc, full);
        }
    } else {
        const patterns: []const []const u8 = if (cfg.include.len > 0) cfg.include else &.{ "**/*.ts", "**/*.tsx", "**/*.mts", "**/*.cts" };
        for (patterns) |pat| {
            const dir_path = std.fs.path.dirname(pat);
            const glob = std.fs.path.basename(pat);
            const search_dir = if (dir_path) |d| try std.fs.path.join(alloc, &.{ base_path, d }) else try alloc.dupe(u8, base_path);
            defer if (dir_path != null) alloc.free(search_dir);

            var dir = std.Io.Dir.cwd().openDir(io, search_dir, .{ .iterate = true }) catch continue;
            defer dir.close(io);
            var walker = try dir.walk(alloc);
            defer walker.deinit();

            while (try walker.next(io)) |entry| {
                if (entry.kind != .file) continue;
                if (!matchGlob(entry.basename, glob)) continue;

                var excluded = false;
                for (cfg.exclude) |ex| {
                    if (std.mem.eql(u8, entry.path, ex) or std.mem.eql(u8, entry.basename, ex)) {
                        excluded = true;
                        break;
                    }
                }
                if (!excluded) {
                    const full = try std.fs.path.join(alloc, &.{ search_dir, entry.path });
                    try result.append(alloc, full);
                }
            }
        }
    }

    return result.toOwnedSlice(alloc);
}

fn matchGlob(name: []const u8, pattern: []const u8) bool {
    if (std.mem.eql(u8, pattern, "*")) return true;
    if (std.mem.startsWith(u8, pattern, "*.")) {
        return std.mem.endsWith(u8, name, pattern[1..]);
    }
    if (std.mem.eql(u8, pattern, name)) return true;
    if (std.mem.endsWith(u8, pattern, "*")) {
        return std.mem.startsWith(u8, name, pattern[0 .. pattern.len - 1]);
    }
    if (std.mem.startsWith(u8, pattern, "**/")) {
        return std.mem.endsWith(u8, name, pattern[3..]);
    }
    return false;
}

pub fn findTsConfig(io: Io, alloc: std.mem.Allocator) ?[]const u8 {
    const cwd = std.process.currentPathAlloc(io, alloc) catch return null;
    defer alloc.free(cwd);

    var dir = alloc.dupe(u8, cwd) catch return null;
    defer alloc.free(dir);

    const config_files = [_][]const u8{ "tsconfig.json", "jsconfig.json", "nxc.config.js", "nxc.json", ".nxrc", ".nxrc.json" };

    while (true) {
        for (config_files) |name| {
            const path = std.fs.path.join(alloc, &.{ dir, name }) catch continue;
            defer alloc.free(path);
            if (std.Io.Dir.cwd().statFile(io, path, .{})) |stat| {
                if (stat.kind == .file) return alloc.dupe(u8, path) catch null;
            } else |_| {}
        }

        const parent = std.fs.path.dirname(dir) orelse break;
        if (parent.len >= dir.len) break;
        const new_dir = alloc.dupe(u8, parent) catch break;
        alloc.free(dir);
        dir = new_dir;
    }

    return null;
}
