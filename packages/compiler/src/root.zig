const std = @import("std");

const ast = @import("ast");
const compiler_core = @import("compiler_core");
const diagnostics = @import("diagnostics");
const parser = @import("parser");
const pipeline = @import("pipeline");

pub const Config = compiler_core.Config;
pub const PathAlias = compiler_core.PathAlias;
pub const CompileResult = compiler_core.CompileResult;
pub const config = compiler_core.config;
pub const findTsConfig = compiler_core.config.findTsConfig;
pub const resolveConfigFiles = compiler_core.config.resolveConfigFiles;
pub const compile = compiler_core.compile;
pub const compileFile = compiler_core.compileFile;
pub const declarationPathFromJsPath = compiler_core.declarationPathFromJsPath;
pub const dupeDiags = compiler_core.dupeDiags;
pub const writeCompileResultFiles = compiler_core.writeCompileResultFiles;

/// Result of parsing TypeScript source. Contains the arena allocator,
/// AST node arena, optional program root node, and diagnostics.
pub const ParseResult = struct {
    arena_backing: std.heap.ArenaAllocator,
    node_arena: ast.Arena,
    program_id: ?ast.NodeId,
    diagnostics: []const diagnostics.Diagnostic,

    pub fn deinit(self: *ParseResult, alloc: std.mem.Allocator) void {
        for (self.diagnostics) |d| {
            alloc.free(d.message);
            alloc.free(d.filename);
            if (d.source_line) |line| alloc.free(line);
        }
        alloc.free(self.diagnostics);
        self.arena_backing.deinit();
    }
};

/// Parse TypeScript/JSX source into an AST. Returns diagnostics on error.
pub fn parse(source: []const u8, filename: []const u8, cfg: Config, alloc: std.mem.Allocator) !ParseResult {
    var arena_backing = std.heap.ArenaAllocator.init(alloc);
    errdefer arena_backing.deinit();
    const a = arena_backing.allocator();

    var diags = diagnostics.DiagnosticList{};
    var node_arena = ast.Arena.init(a);
    const parse_opts = parser.ParseOptions{
        .typescript = cfg.parser.syntax == .typescript,
        .jsx = cfg.jsx,
        .source_type = .module,
        .check = cfg.check,
    };

    var p = parser.Parser.init(source, filename, &node_arena, a, &diags, parse_opts);
    const program_id = p.parseProgram() catch |err| blk: {
        if (err == error.ParseError) break :blk null;
        return err;
    };

    return .{
        .arena_backing = arena_backing,
        .node_arena = node_arena,
        .program_id = program_id,
        .diagnostics = try compiler_core.dupeDiags(&diags.items, alloc),
    };
}

/// Compile TypeScript/JSX source to JavaScript, including all transforms.
/// Returns CompileResult with code, optional source map, and optional .d.ts output.
pub fn transform(source: []const u8, filename: []const u8, cfg: Config, io: std.Io, alloc: std.mem.Allocator) !CompileResult {
    return compile(source, filename, cfg, io, alloc);
}

/// Apply transforms to an already-parsed AST (type stripping, JSX, decorators, etc.).
pub fn transformParsed(result: *ParseResult, filename: []const u8, cfg: Config, io: std.Io, alloc: std.mem.Allocator) !void {
    const program_id = result.program_id orelse return error.ParseError;
    try pipeline.run(&result.node_arena, result.arena_backing.allocator(), io, .{
        .typescript = cfg.parser.syntax == .typescript,
        .jsx = cfg.jsx,
        .jsx_cfg = .{
            .runtime = cfg.transform.react.jsx_runtime,
            .factory = cfg.transform.react.jsx_factory,
            .fragment = cfg.transform.react.jsx_fragment,
            .import_source = cfg.transform.react.jsx_import_source,
        },
        .src_file = filename,
        .module_strict = cfg.module.strict,
        .esmodule_interop = cfg.module.es_module_interop,
        .import_interop = cfg.module.import_interop,
        .decorators = cfg.parser.decorators,
        .legacy_decorator = cfg.transform.legacy_decorator,
        .decorator_metadata = cfg.transform.decorator_metadata,
        .aliases_cfg = .{ .aliases = cfg.paths, .src_file = filename },
        .paths_cfg = .{
            .add_js_extension = cfg.module.resolve_full_paths,
            .src_file = filename,
            .src_dir = std.fs.path.dirname(filename) orelse ".",
            .base_url = cfg.base_url,
        },
        .remove_comments = cfg.remove_comments,
        .target = switch (cfg.target) {
            .es2015, .es2016, .es2017, .es2018, .es2019 => .es2015,
            .es2020 => .es2020,
            .es2022 => .es2022,
            .es2024 => .es2024,
            .esnext => .esnext,
        },
    }, program_id);
    _ = alloc;
}
