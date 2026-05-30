const std = @import("std");
const common = @import("common");
const formatter = @import("formatter.zig");
const ast = @import("ast.zig");
const parser = @import("parser.zig");
const rules = @import("rules.zig");
const json5 = @import("json5.zig");

pub const Severity = common.Severity;
pub const Diagnostic = common.Diagnostic;
pub const SourceRange = common.SourceRange;
pub const Env = common.LintEnvironment;

pub const PluginInfo = struct {
    name: []const u8,
    version: []const u8,
};

pub const RuleOverride = struct {
    code: []const u8,
    enabled: bool = true,
    severity: ?Severity = null,
    option_bool: ?bool = null,
    option_string: ?[]const u8 = null,
    option_int: ?i64 = null,

    pub fn deinit(self: RuleOverride, alloc: std.mem.Allocator) void {
        alloc.free(self.code);
        if (self.option_string) |s| alloc.free(s);
    }
};

pub const FormatterConfig = struct {
    options: common.FormatterOptions = .{},

    pub fn deinit(_: *FormatterConfig) void {}
};

pub const Config = struct {
    env: Env = .{},
    formatter: FormatterConfig = .{},
    rule_overrides: std.ArrayListUnmanaged(RuleOverride) = .empty,
    formatter_path: ?[]const u8 = null,

    pub fn deinit(self: *Config, alloc: std.mem.Allocator) void {
        for (self.rule_overrides.items) |o| o.deinit(alloc);
        self.rule_overrides.deinit(alloc);
        if (self.formatter_path) |p| alloc.free(p);
    }
};

pub const Registry = struct {
    rules: std.ArrayListUnmanaged(common.LintRule) = .empty,
    plugins: std.ArrayListUnmanaged(PluginInfo) = .empty,

    pub fn deinit(self: *Registry, alloc: std.mem.Allocator) void {
        for (self.rules.items) |rule| alloc.free(rule.code);
        self.rules.deinit(alloc);
        for (self.plugins.items) |plugin| {
            alloc.free(plugin.name);
            alloc.free(plugin.version);
        }
        self.plugins.deinit(alloc);
    }

    pub fn register(self: *Registry, alloc: std.mem.Allocator, rule: common.LintRule) !void {
        try self.registerWithCode(alloc, rule, rule.code);
    }

    pub fn registerPlugin(self: *Registry, alloc: std.mem.Allocator, plugin: common.Plugin) !void {
        try self.plugins.append(alloc, .{
            .name = try alloc.dupe(u8, plugin.name),
            .version = try alloc.dupe(u8, plugin.version),
        });

        if (plugin.setup_linter) |setup| try setup(self, alloc);
        for (plugin.lint_rules) |rule| try self.registerPluginRule(alloc, plugin.name, rule);
    }

    pub fn registerPluginRule(self: *Registry, alloc: std.mem.Allocator, plugin_name: []const u8, rule: common.LintRule) !void {
        if (std.mem.indexOfScalar(u8, rule.code, '/') != null) {
            try self.registerWithCode(alloc, rule, rule.code);
            return;
        }

        const full_code = try std.fmt.allocPrint(alloc, "{s}/{s}", .{ plugin_name, rule.code });
        defer alloc.free(full_code);
        try self.registerWithCode(alloc, rule, full_code);
    }

    fn registerWithCode(self: *Registry, alloc: std.mem.Allocator, rule: common.LintRule, code: []const u8) !void {
        var owned = rule;
        owned.code = try alloc.dupe(u8, code);
        errdefer alloc.free(owned.code);
        try self.rules.append(alloc, owned);
    }
};

pub const format = formatter.format;
pub const FormatDiagnostic = formatter.FormatDiagnostic;
pub const registerFormatterRules = formatter.registerFormatterRules;
pub const checkFormat = formatter.checkFormat;
pub const buildFmtOptsFromRule = formatter.buildFmtOptsFromRule;
pub const fmtRuleMessage = formatter.fmtRuleMessage;
pub const freeCheckDiagnostics = formatter.freeCheckDiagnostics;

pub const Result = struct {
    diagnostics: []Diagnostic,
    formatted: ?[]const u8 = null,
    fixed_source: ?[]const u8 = null,

    pub fn deinit(self: Result, alloc: std.mem.Allocator) void {
        common.freeDiagnostics(alloc, self.diagnostics);
        if (self.formatted) |formatted| alloc.free(formatted);
        if (self.fixed_source) |fixed| alloc.free(fixed);
    }
};

fn applyRuleOverrides(registry: *Registry, overrides: std.ArrayListUnmanaged(RuleOverride), alloc: std.mem.Allocator) void {
    for (overrides.items) |o| {
        var i: usize = 0;
        while (i < registry.rules.items.len) {
            const rule = &registry.rules.items[i];
            if (std.mem.eql(u8, rule.code, o.code)) {
                if (!o.enabled) {
                    alloc.free(rule.code);
                    _ = registry.rules.swapRemove(i);
                } else {
                    if (o.severity) |sev| rule.severity = sev;
                    if (o.option_bool) |v| rule.options = .{ .bool_val = v };
                    if (o.option_string) |v| rule.options = .{ .string_val = v };
                    if (o.option_int) |v| rule.options = .{ .int_val = v };
                    i += 1;
                }
                break;
            }
            i += 1;
        }
    }
}

fn applyFormatterConfigToRules(registry: *Registry, opts: common.FormatterOptions) void {
    const Entry = struct { code: []const u8, option: common.RuleOptions };
    const entries = [_]Entry{
        .{ .code = "formatter/quotes", .option = .{ .bool_val = opts.singleQuote } },
        .{ .code = "formatter/semi", .option = .{ .bool_val = opts.semi } },
        .{ .code = "formatter/trailing-comma", .option = .{ .string_val = @tagName(opts.trailingComma) } },
        .{ .code = "formatter/bracket-spacing", .option = .{ .bool_val = opts.bracketSpacing } },
        .{ .code = "formatter/use-tabs", .option = .{ .bool_val = opts.useTabs } },
        .{ .code = "formatter/tab-width", .option = .{ .int_val = @as(i64, @intCast(opts.tabWidth)) } },
        .{ .code = "formatter/print-width", .option = .{ .int_val = @as(i64, @intCast(opts.printWidth)) } },
        .{ .code = "formatter/arrow-parens", .option = .{ .string_val = @tagName(opts.arrowParens) } },
        .{ .code = "formatter/end-of-line", .option = .{ .string_val = @tagName(opts.endOfLine) } },
        .{ .code = "formatter/bracket-same-line", .option = .{ .bool_val = opts.bracketSameLine } },
    };
    for (&entries) |entry| {
        for (registry.rules.items) |*rule| {
            if (std.mem.eql(u8, rule.code, entry.code)) {
                rule.options = entry.option;
                rule.severity = .warn;
                break;
            }
        }
    }
}

/// Lint source code using a pre-configured rule registry.
/// Returns Result with diagnostics and optional fixed source.
pub fn lint(source: []const u8, filename: []const u8, registry: Registry, alloc: std.mem.Allocator) !Result {
    return lintWithEnv(source, filename, registry, .{}, alloc);
}

fn lintWithEnv(source: []const u8, filename: []const u8, registry: Registry, env: Env, alloc: std.mem.Allocator) !Result {
    var arena_backing = std.heap.ArenaAllocator.init(alloc);
    defer arena_backing.deinit();
    const a = arena_backing.allocator();

    var node_arena = ast.Arena.init(a);
    var diags = parser.diagnostics.DiagnosticList{};
    const parse_opts = parser.ParseOptions{
        .typescript = true,
        .jsx = true,
        .source_type = .module,
        .check = false,
    };
    var p = parser.Parser.init(source, filename, &node_arena, a, &diags, parse_opts);
    const program_id = p.parseProgram() catch null;

    var diagnostics = std.ArrayListUnmanaged(Diagnostic).empty;
    errdefer {
        for (diagnostics.items) |diag| common.freeDiagnostic(alloc, diag);
        diagnostics.deinit(alloc);
    }

    var fixes = std.ArrayListUnmanaged(common.LintFix).empty;
    errdefer {
        for (fixes.items) |f| alloc.free(f.replacement);
        fixes.deinit(alloc);
    }

    const builtin_visitors = rules.buildVisitors();

    var active_visitors = std.ArrayListUnmanaged(rules.RuleVisitor).empty;
    defer active_visitors.deinit(alloc);

    if (program_id != null) {
        for (registry.rules.items) |rule| {
            if (rule.severity == .off) continue;
            for (builtin_visitors) |v| {
                if (std.mem.eql(u8, rule.code, v.rule.code)) {
                    var adapted = v;
                    adapted.rule = rule;
                    try active_visitors.append(alloc, adapted);
                    break;
                }
            }
        }
    }

    if (active_visitors.items.len > 0) {
        try rules.scanAllNodes(.{
            .source = source,
            .filename = filename,
            .env = env,
            .alloc = alloc,
            .diagnostics = &diagnostics,
            .fixes = &fixes,
            .ast_arena = @ptrCast(&node_arena),
            .ast_program_id = @as(u32, program_id.?),
        }, active_visitors.items);
    }

    for (registry.rules.items) |rule| {
        if (rule.severity == .off) continue;

        var already_visited = false;
        for (builtin_visitors) |v| {
            if (std.mem.eql(u8, rule.code, v.rule.code)) {
                already_visited = true;
                break;
            }
        }
        if (already_visited) continue;

        try rule.run(.{
            .source = source,
            .filename = filename,
            .env = env,
            .alloc = alloc,
            .diagnostics = &diagnostics,
            .fixes = &fixes,
            .ast_arena = if (program_id != null) @ptrCast(&node_arena) else null,
            .ast_program_id = if (program_id) |pid| @as(u32, pid) else null,
        }, rule);
    }

    for (registry.rules.items) |rule| {
        if (rule.fix) |fix_fn| {
            if (rule.severity == .off) continue;
            if (program_id == null) continue;
            try fix_fn(.{
                .source = source,
                .filename = filename,
                .env = env,
                .alloc = alloc,
                .diagnostics = &diagnostics,
                .fixes = &fixes,
                .ast_arena = @ptrCast(&node_arena),
                .ast_program_id = @as(u32, program_id.?),
            }, rule);
        }
    }

    var fixed_source: ?[]const u8 = null;
    if (fixes.items.len > 0) {
        std.sort.insertion(common.LintFix, fixes.items, {}, struct {
            fn lessThan(_: void, lhs: common.LintFix, rhs: common.LintFix) bool {
                return lhs.start < rhs.start;
            }
        }.lessThan);

        var total_len: usize = source.len;
        var prev_src: usize = 0;
        for (fixes.items) |f| {
            if (f.start < prev_src) continue;
            total_len = total_len - (f.end - f.start) + f.replacement.len;
            prev_src = f.start;
        }

        var result = try alloc.alloc(u8, total_len);
        var dst: usize = 0;
        var src: usize = 0;

        for (fixes.items) |f| {
            if (f.start < src) continue;
            const before_len = f.start - src;
            @memcpy(result[dst..][0..before_len], source[src..][0..before_len]);
            dst += before_len;
            @memcpy(result[dst..][0..f.replacement.len], f.replacement);
            dst += f.replacement.len;
            src = f.end;
        }
        if (src < source.len) {
            @memcpy(result[dst..], source[src..]);
        }

        fixed_source = result;

        for (fixes.items) |f| alloc.free(f.replacement);
        fixes.deinit(alloc);
    }

    return .{
        .diagnostics = try diagnostics.toOwnedSlice(alloc),
        .fixed_source = fixed_source,
    };
}

pub fn lintAndFormat(source: []const u8, filename: []const u8, registry: Registry, cfg: Config, alloc: std.mem.Allocator) !Result {
    var result = try lintWithEnv(source, filename, registry, cfg.env, alloc);
    errdefer result.deinit(alloc);

    const base = result.fixed_source orelse source;
    result.formatted = try formatter.format(base, cfg.formatter.options, alloc);

    return result;
}

/// Lint source code using the built-in default rule set. Quick entry point.
pub fn lintWithDefaultRules(source: []const u8, filename: []const u8, alloc: std.mem.Allocator) !Result {
    var registry = Registry{};
    defer registry.deinit(alloc);
    try registerDefaultRules(&registry, alloc);
    return lint(source, filename, registry, alloc);
}

/// Lint source code with a custom Config (env, rules, formatter options).
pub fn lintWithConfig(source: []const u8, filename: []const u8, cfg: Config, alloc: std.mem.Allocator) !Result {
    var registry = Registry{};
    defer registry.deinit(alloc);
    try registerDefaultRules(&registry, alloc);

    applyFormatterConfigToRules(&registry, cfg.formatter.options);
    applyRuleOverrides(&registry, cfg.rule_overrides, alloc);
    return lintAndFormat(source, filename, registry, cfg, alloc);
}

/// Lint source with custom third-party plugins. Plugins can add rules and formatters.
pub fn lintWithPlugins(source: []const u8, filename: []const u8, plugins: []const common.Plugin, alloc: std.mem.Allocator) !Result {
    var registry = Registry{};
    defer registry.deinit(alloc);
    try registerDefaultRules(&registry, alloc);
    for (plugins) |plugin| try registry.registerPlugin(alloc, plugin);
    return lint(source, filename, registry, alloc);
}

/// Full linter: plugins + config + default rules combined.
pub fn lintWithPluginsAndConfig(source: []const u8, filename: []const u8, plugins: []const common.Plugin, cfg: Config, alloc: std.mem.Allocator) !Result {
    var registry = Registry{};
    defer registry.deinit(alloc);
    try registerDefaultRules(&registry, alloc);
    for (plugins) |plugin| try registry.registerPlugin(alloc, plugin);

    applyFormatterConfigToRules(&registry, cfg.formatter.options);
    applyRuleOverrides(&registry, cfg.rule_overrides, alloc);
    return lintAndFormat(source, filename, registry, cfg, alloc);
}

pub fn readAndParseConfig(path: []const u8, io: std.Io, alloc: std.mem.Allocator) !Config {
    if (std.mem.endsWith(u8, path, ".js")) {
        return readJsConfig(path, io, alloc);
    }
    const source = try common.readFileAlloc(path, io, alloc);
    defer alloc.free(source);
    return try parseConfig(source, alloc);
}

pub fn readConfigFile(path: []const u8, io: std.Io, alloc: std.mem.Allocator) !Config {
    return readAndParseConfig(path, io, alloc);
}

fn readJsConfig(path: []const u8, io: std.Io, alloc: std.mem.Allocator) !Config {
    const eval_script =
        \\globalThis.defineConfig = c => c;
        \\import { pathToFileURL } from 'node:url';
        \\import(pathToFileURL(process.argv[1]).href).then(m => {
        \\  const config = m.default ?? m;
        \\  console.log(JSON.stringify(config));
        \\}).catch(err => {
        \\  console.error('Config error:', err.message);
        \\  process.exit(1);
        \\});
    ;

    const result = std.process.run(alloc, io, .{
        .argv = &.{ "node", "--input-type=module", "-e", eval_script, path },
    }) catch return Config{};
    defer alloc.free(result.stdout);
    defer alloc.free(result.stderr);

    switch (result.term) {
        .exited => |code| if (code != 0) return Config{},
        else => return Config{},
    }

    const json_str = std.mem.trim(u8, result.stdout, " \t\n\r");
    if (json_str.len == 0) return Config{};

    return parseJsonConfig(json_str, alloc);
}

const config_filenames = [_][]const u8{"nxc.config.js"};

pub fn searchConfig(start_dir: []const u8, io: std.Io, alloc: std.mem.Allocator) Config {
    var dir = alloc.dupe(u8, start_dir) catch return Config{};
    defer alloc.free(dir);

    while (true) {
        for (config_filenames) |filename| {
            const path = std.fs.path.join(alloc, &.{ dir, filename }) catch continue;
            defer alloc.free(path);

            if (readAndParseConfig(path, io, alloc)) |cfg| return cfg else |_| continue;
        }

        const parent = std.fs.path.dirname(dir) orelse break;
        if (parent.len >= dir.len) break;
        const new_dir = alloc.dupe(u8, parent) catch break;
        alloc.free(dir);
        dir = new_dir;
    }

    return Config{};
}

pub fn searchConfigCwd(io: std.Io, alloc: std.mem.Allocator) Config {
    const cwd = std.process.currentPathAlloc(io, alloc) catch return Config{};
    defer alloc.free(cwd);
    return searchConfig(cwd, io, alloc);
}

fn parseSeverity(s: []const u8) ?Severity {
    if (std.mem.eql(u8, s, "error")) return .err;
    if (std.mem.eql(u8, s, "warn")) return .warn;
    if (std.mem.eql(u8, s, "info")) return .info;
    return null;
}

pub fn parseConfig(source: []const u8, alloc: std.mem.Allocator) !Config {
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const a = arena.allocator();

    const body = extractJson5Body(source) orelse return Config{};
    const trimmed = std.mem.trimEnd(u8, body, "; \t\n\r");

    const parsed = json5.parse(trimmed, a) catch return Config{};
    defer parsed.deinit();

    return parseJsonValue(parsed.value, alloc);
}

fn parseJsonConfig(json_str: []const u8, alloc: std.mem.Allocator) !Config {
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const a = arena.allocator();

    const parsed = json5.parse(json_str, a) catch return Config{};
    defer parsed.deinit();

    return parseJsonValue(parsed.value, alloc);
}

fn parseJsonValue(root: std.json.Value, alloc: std.mem.Allocator) !Config {
    var cfg = Config{};

    if (root == .array) {
        for (root.array.items) |item| {
            if (item == .object) {
                try parseConfigObject(item.object, &cfg, alloc);
            }
        }
        return cfg;
    }

    if (root == .object) {
        try parseConfigObject(root.object, &cfg, alloc);
    }

    return cfg;
}

fn parseConfigObject(obj: std.json.ObjectMap, cfg: *Config, alloc: std.mem.Allocator) !void {
    if (obj.get("env")) |env_val| {
        if (env_val == .object) {
            const env_obj = env_val.object;
            if (env_obj.get("node")) |v| { if (v == .bool) cfg.env.node = cfg.env.node or v.bool; }
            if (env_obj.get("deno")) |v| { if (v == .bool) cfg.env.deno = cfg.env.deno or v.bool; }
            if (env_obj.get("bun")) |v| { if (v == .bool) cfg.env.bun = cfg.env.bun or v.bool; }
        }
    }

    if (obj.get("formatter")) |fmt_val| {
        if (fmt_val == .object) {
            parseFormatterOptions(fmt_val.object, &cfg.formatter.options);
        }
    }

    if (obj.get("linter")) |linter_val| {
        if (linter_val == .array) {
            for (linter_val.array.items) |item| {
                if (item == .object) {
                    if (item.object.get("rules")) |rules_val| {
                        try parseRuleOverridesDedup(rules_val, &cfg.rule_overrides, alloc);
                    }
                }
            }
        } else if (linter_val == .object) {
            if (linter_val.object.get("rules")) |rules_val| {
                try parseRuleOverridesDedup(rules_val, &cfg.rule_overrides, alloc);
            }
        }
    }

    const top_rules = obj.get("rules") orelse obj.get("rule_overrides");
    if (top_rules) |rules_val| {
        try parseRuleOverridesDedup(rules_val, &cfg.rule_overrides, alloc);
    }
}

fn parseRuleOverrides(rules_val: std.json.Value, overrides: *std.ArrayListUnmanaged(RuleOverride), alloc: std.mem.Allocator) !void {
    if (rules_val != .object) return;
    var it = rules_val.object.iterator();
    while (it.next()) |entry| {
        try parseSingleOverride(entry.key_ptr.*, entry.value_ptr.*, overrides, alloc);
    }
}

fn parseRuleOverridesDedup(rules_val: std.json.Value, overrides: *std.ArrayListUnmanaged(RuleOverride), alloc: std.mem.Allocator) !void {
    if (rules_val != .object) return;
    var it = rules_val.object.iterator();
    while (it.next()) |entry| {
        const code = entry.key_ptr.*;
        var already = false;
        for (overrides.items) |o| {
            if (std.mem.eql(u8, o.code, code)) {
                already = true;
                break;
            }
        }
        if (already) continue;
        try parseSingleOverride(code, entry.value_ptr.*, overrides, alloc);
    }
}

fn parseSingleOverride(code: []const u8, val: std.json.Value, overrides: *std.ArrayListUnmanaged(RuleOverride), alloc: std.mem.Allocator) !void {
    var override = RuleOverride{ .code = try alloc.dupe(u8, code) };
    if (val == .string) {
        const s = val.string;
        if (std.mem.eql(u8, s, "off")) {
            override.enabled = false;
        } else if (parseSeverity(s)) |sev| {
            override.severity = sev;
        }
    } else if (val == .array and val.array.items.len >= 1) {
        const first = val.array.items[0];
        if (first == .string) {
            const s = first.string;
            if (std.mem.eql(u8, s, "off")) {
                override.enabled = false;
            } else if (parseSeverity(s)) |sev| {
                override.severity = sev;
            }
        }
        if (val.array.items.len >= 2) {
            const second = val.array.items[1];
            if (second == .bool) {
                override.option_bool = second.bool;
            } else if (second == .string) {
                override.option_string = try alloc.dupe(u8, second.string);
            } else if (second == .integer) {
                override.option_int = second.integer;
            }
        }
    } else if (val == .integer) {
        if (val.integer == 0) {
            override.enabled = false;
        } else if (val.integer == 1) {
            override.severity = .warn;
        } else if (val.integer == 2) {
            override.severity = .err;
        }
    }
    try overrides.append(alloc, override);
}

fn parseFormatterOptions(fmt_obj: std.json.ObjectMap, opts: *common.FormatterOptions) void {
    if (fmt_obj.get("semi")) |v| { if (v == .bool) opts.semi = v.bool; }
    if (fmt_obj.get("singleQuote")) |v| { if (v == .bool) opts.singleQuote = v.bool; }
    if (fmt_obj.get("jsxSingleQuote")) |v| { if (v == .bool) opts.jsxSingleQuote = v.bool; }
    if (fmt_obj.get("operatorPosition")) |v| {
        if (v == .string) {
            opts.operatorPosition = std.meta.stringToEnum(common.OperatorPosition, v.string) orelse .end;
        }
    }
    if (fmt_obj.get("ternaryStyle")) |v| {
        if (v == .string) {
            opts.ternaryStyle = std.meta.stringToEnum(common.TernaryStyle, v.string) orelse .classic;
        }
    }
    if (fmt_obj.get("bracketSpacing")) |v| { if (v == .bool) opts.bracketSpacing = v.bool; }
    if (fmt_obj.get("useTabs")) |v| { if (v == .bool) opts.useTabs = v.bool; }
    if (fmt_obj.get("trailingComma")) |v| {
        if (v == .string) {
            opts.trailingComma = std.meta.stringToEnum(common.TrailingComma, v.string) orelse .all;
        }
    }
    if (fmt_obj.get("quoteProps")) |v| {
        if (v == .string) {
            const normalized = if (std.mem.eql(u8, v.string, "as-needed")) "as_needed" else v.string;
            opts.quoteProps = std.meta.stringToEnum(common.QuoteProps, normalized) orelse .as_needed;
        }
    }
    if (fmt_obj.get("arrowParens")) |v| {
        if (v == .string) {
            opts.arrowParens = std.meta.stringToEnum(common.ArrowParens, v.string) orelse .always;
        }
    }
    if (fmt_obj.get("endOfLine")) |v| {
        if (v == .string) {
            opts.endOfLine = std.meta.stringToEnum(common.EndOfLine, v.string) orelse .lf;
        }
    }
    if (fmt_obj.get("tabWidth")) |v| {
        if (v == .integer and v.integer >= 0) opts.tabWidth = @intCast(v.integer);
    }
    if (fmt_obj.get("printWidth")) |v| {
        if (v == .integer and v.integer >= 0) opts.printWidth = @intCast(v.integer);
    }
    if (fmt_obj.get("proseWrap")) |v| {
        if (v == .string) {
            opts.proseWrap = std.meta.stringToEnum(common.ProseWrap, v.string) orelse .preserve;
        }
    }
    if (fmt_obj.get("objectWrap")) |v| {
        if (v == .string) {
            opts.objectWrap = std.meta.stringToEnum(common.ObjectWrap, v.string) orelse .preserve;
        }
    }
    if (fmt_obj.get("singleAttributePerLine")) |v| { if (v == .bool) opts.singleAttributePerLine = v.bool; }
    if (fmt_obj.get("bracketSameLine")) |v| { if (v == .bool) opts.bracketSameLine = v.bool; }
    if (fmt_obj.get("requirePragma")) |v| { if (v == .bool) opts.requirePragma = v.bool; }
    if (fmt_obj.get("insertPragma")) |v| { if (v == .bool) opts.insertPragma = v.bool; }
    if (fmt_obj.get("checkIgnorePragma")) |v| { if (v == .bool) opts.checkIgnorePragma = v.bool; }
    if (fmt_obj.get("embeddedLanguageFormatting")) |v| {
        if (v == .string) {
            opts.embeddedLanguageFormatting = std.meta.stringToEnum(common.EmbeddedLanguageFormatting, v.string) orelse .auto;
        }
    }
    if (fmt_obj.get("rangeStart")) |v| {
        if (v == .integer and v.integer >= 0) opts.rangeStart = @intCast(v.integer);
    }
    if (fmt_obj.get("rangeEnd")) |v| {
        if (v == .integer and v.integer >= 0) opts.rangeEnd = @intCast(v.integer);
    }
}

pub fn readAndParseFormatterConfig(path: []const u8, io: std.Io, alloc: std.mem.Allocator) !FormatterConfig {
    const cfg = try readAndParseConfig(path, io, alloc);
    return cfg.formatter;
}

pub fn parseFormatterConfig(source: []const u8, alloc: std.mem.Allocator) !FormatterConfig {
    var cfg = try parseConfig(source, alloc);
    defer cfg.deinit(alloc);
    return cfg.formatter;
}

fn extractJson5Body(source: []const u8) ?[]const u8 {
    var s = source;

    if (s.len >= 3 and s[0] == 0xEF and s[1] == 0xBB and s[2] == 0xBF) s = s[3..];

    var changed = true;
    while (changed) {
        changed = false;

        if (std.mem.indexOf(u8, s, "export default")) |idx| {
            s = s[idx + "export default".len..];
            changed = true;
            continue;
        }

        if (std.mem.indexOf(u8, s, "module.exports")) |idx| {
            const after = s[idx + "module.exports".len..];
            if (std.mem.indexOf(u8, after, "=")) |eq_idx| {
                s = std.mem.trimStart(u8, after[eq_idx + 1 ..], " \t\n\r");
                changed = true;
                continue;
            }
        }

        if (std.mem.indexOf(u8, s, "defineConfig")) |idx| {
            const rest = std.mem.trimStart(u8, s[idx + "defineConfig".len..], " \t\n\r");
            if (rest.len > 0 and rest[0] == '(') {
                var depth: usize = 1;
                var i: usize = 1;
                while (i < rest.len and depth > 0) {
                    switch (rest[i]) {
                        '(' => depth += 1,
                        ')' => depth -= 1,
                        else => {},
                    }
                    i += 1;
                }
                if (depth == 0) {
                    s = rest[1 .. i - 1];
                    changed = true;
                    continue;
                }
            }
        }
    }

    if (s.len > 0 and s[0] == '[') {
        var depth: usize = 0;
        var i: usize = 0;
        while (i < s.len) {
            switch (s[i]) {
                '[' => depth += 1,
                ']' => {
                    depth -= 1;
                    if (depth == 0) return s[0 .. i + 1];
                },
                '"' => {
                    i += 1;
                    while (i < s.len and s[i] != '"') {
                        if (s[i] == '\\') i += 1;
                        i += 1;
                    }
                },
                '\'' => {
                    i += 1;
                    while (i < s.len and s[i] != '\'') {
                        if (s[i] == '\\') i += 1;
                        i += 1;
                    }
                },
                else => {},
            }
            i += 1;
        }
        return null;
    }

    return extractOuterObject(s);
}

fn extractOuterObject(s: []const u8) ?[]const u8 {
    const start = std.mem.indexOf(u8, s, "{") orelse return null;
    var depth: usize = 0;
    var i = start;
    while (i < s.len) {
        switch (s[i]) {
            '{' => depth += 1,
            '}' => {
                depth -= 1;
                if (depth == 0) return s[start .. i + 1];
            },
            '"' => {
                i += 1;
                while (i < s.len and s[i] != '"') {
                    if (s[i] == '\\') i += 1;
                    i += 1;
                }
            },
            '\'' => {
                i += 1;
                while (i < s.len and s[i] != '\'') {
                    if (s[i] == '\\') i += 1;
                    i += 1;
                }
            },
            else => {},
        }
        i += 1;
    }
    return null;
}

pub fn registerDefaultRules(registry: *Registry, alloc: std.mem.Allocator) !void {
    try rules.registerAll(registry, alloc);
    try registry.register(alloc, noProcessExitRule());
    try formatter.registerFormatterRules(registry, alloc);
}

pub const registerRecommendedRules = rules.registerAll;

pub fn noProcessExitRule() common.LintRule {
    return .{ .code = "no-process-exit", .severity = .err, .run = runNoProcessExit };
}

fn runNoProcessExit(ctx: common.LintContext, rule: common.LintRule) !void {
    if (!ctx.env.node) return;
    var start: usize = 0;
    while (std.mem.indexOfPos(u8, ctx.source, start, "process.exit")) |idx| {
        const end = idx + "process.exit".len;
        try ctx.report(rule.code, rule.severity, "unexpected process.exit() call", idx, end);
        start = end;
    }
}
