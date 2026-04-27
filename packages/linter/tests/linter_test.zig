const std = @import("std");

const common = @import("common");
const linter = @import("linter");

test "linter package runs default rules" {
    const result = try linter.lintWithDefaultRules("debugger;", "test.ts", std.testing.allocator);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), result.diagnostics.len);
    try std.testing.expectEqualStrings("no-debugger", result.diagnostics[0].rule_code);
    try std.testing.expectEqual(linter.Severity.err, result.diagnostics[0].severity);
}

test "linter package allows registering rules" {
    var registry = linter.Registry{};
    defer registry.deinit(std.testing.allocator);
    try registry.register(std.testing.allocator, .{ .code = "custom", .severity = .err, .run = customRule });

    const result = try linter.lint("source", "test.ts", registry, std.testing.allocator);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), result.diagnostics.len);
    try std.testing.expectEqualStrings("custom", result.diagnostics[0].rule_code);
}

fn customRule(ctx: common.LintContext, rule: common.LintRule) !void {
    try ctx.report(rule.code, rule.severity, "custom diagnostic", 0, 1);
}

test "linter package allows registering plugin rules" {
    var registry = linter.Registry{};
    defer registry.deinit(std.testing.allocator);
    try registry.registerPlugin(std.testing.allocator, .{
        .name = "node",
        .version = "0.1.0",
        .lint_rules = &.{.{ .code = "no-process-exit", .severity = .err, .run = nodeRule }},
    });

    const result = try linter.lint("process.exit(1);", "test.ts", registry, std.testing.allocator);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), result.diagnostics.len);
    try std.testing.expectEqualStrings("node/no-process-exit", result.diagnostics[0].rule_code);
    try std.testing.expectEqual(linter.Severity.err, result.diagnostics[0].severity);
}

test "linter package lintWithPlugins includes default and plugin rules" {
    const plugins = [_]common.Plugin{.{
        .name = "react",
        .lint_rules = &.{.{ .code = "jsx-key", .severity = .warn, .run = reactRule }},
    }};

    const result = try linter.lintWithPlugins("debugger; <Item />", "test.tsx", &plugins, std.testing.allocator);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), result.diagnostics.len);
    try std.testing.expectEqualStrings("no-debugger", result.diagnostics[0].rule_code);
    try std.testing.expectEqualStrings("react/jsx-key", result.diagnostics[1].rule_code);
}

fn nodeRule(ctx: common.LintContext, rule: common.LintRule) !void {
    if (std.mem.indexOf(u8, ctx.source, "process.exit")) |idx| {
        try ctx.report(rule.code, rule.severity, "unexpected process.exit", idx, idx + "process.exit".len);
    }
}

fn reactRule(ctx: common.LintContext, rule: common.LintRule) !void {
    if (std.mem.indexOf(u8, ctx.source, "<Item")) |idx| {
        try ctx.report(rule.code, rule.severity, "missing key prop", idx, idx + "<Item".len);
    }
}

test "linter package can run formatter with lint" {
    const result = try linter.lintWithConfig("const x = 'a'", "test.ts", .{}, std.testing.allocator);
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.formatted != null);
    try std.testing.expectEqualStrings("const x = \"a\";", result.formatted.?);
}

test "linter package config accepts formatter object with options" {
    var cfg = try linter.parseConfig(
        \\module.exports = {
        \\ formatter: { singleQuote: true, semi: false },
        \\};
    , std.testing.allocator);
    defer cfg.deinit(std.testing.allocator);

    try std.testing.expectEqual(true, cfg.formatter.options.singleQuote);
    try std.testing.expectEqual(false, cfg.formatter.options.semi);
}

test "linter package config maps formatter style" {
    var cfg = try linter.parseConfig(
        \\export default { formatter: { singleQuote: true, semi: false } };
    , std.testing.allocator);
    defer cfg.deinit(std.testing.allocator);

    try std.testing.expectEqual(true, cfg.formatter.options.singleQuote);
    try std.testing.expectEqual(false, cfg.formatter.options.semi);
}

test "linter package config supports esm defineConfig" {
    var cfg = try linter.parseConfig(
        \\import { defineConfig } from "nxc/linter";
        \\export default defineConfig({
        \\ formatter: { singleQuote: true },
        \\});
    , std.testing.allocator);
    defer cfg.deinit(std.testing.allocator);

    try std.testing.expectEqual(true, cfg.formatter.options.singleQuote);
}

test "linter package config supports linter json schema" {
    var cfg = try linter.parseConfig(
        \\{
        \\ "$schema": "https://example.com/linter.schema.json",
        \\ "formatter": {
        \\ "singleQuote": true,
        \\ "semi": false
        \\ }
        \\}
    , std.testing.allocator);
    defer cfg.deinit(std.testing.allocator);

    try std.testing.expectEqual(true, cfg.formatter.options.singleQuote);
    try std.testing.expectEqual(false, cfg.formatter.options.semi);
}

test "linter package config supports prettier-like formatter options" {
    var cfg = try linter.parseConfig(
        \\export default defineConfig({
        \\  formatter: {
        \\    singleQuote: true,
        \\    trailingComma: 'none',
        \\    bracketSpacing: true,
        \\    quoteProps: 'preserve',
        \\    semi: false,
        \\    arrowParens: 'always',
        \\    endOfLine: 'lf',
        \\    useTabs: false,
        \\  },
        \\});
    , std.testing.allocator);
    defer cfg.deinit(std.testing.allocator);

    try std.testing.expectEqual(true, cfg.formatter.options.singleQuote);
    try std.testing.expectEqual(.none, cfg.formatter.options.trailingComma);
    try std.testing.expectEqual(true, cfg.formatter.options.bracketSpacing);
    try std.testing.expectEqual(.preserve, cfg.formatter.options.quoteProps);
    try std.testing.expectEqual(false, cfg.formatter.options.semi);
    try std.testing.expectEqual(.always, cfg.formatter.options.arrowParens);
    try std.testing.expectEqual(.lf, cfg.formatter.options.endOfLine);
    try std.testing.expectEqual(false, cfg.formatter.options.useTabs);
}

test "linter package config supports node deno and bun env" {
    var cfg = try linter.parseConfig(
        \\export default defineConfig({
        \\  env: {
        \\    node: true,
        \\    deno: true,
        \\    bun: false,
        \\  },
        \\});
    , std.testing.allocator);
    defer cfg.deinit(std.testing.allocator);

    try std.testing.expectEqual(true, cfg.env.node);
    try std.testing.expectEqual(true, cfg.env.deno);
    try std.testing.expectEqual(false, cfg.env.bun);
}

test "linter package passes env to rules" {
    var registry = linter.Registry{};
    defer registry.deinit(std.testing.allocator);
    try registry.register(std.testing.allocator, .{ .code = "env-check", .severity = .err, .run = envRule });

    const result = try linter.lintAndFormat("process.exit(1)", "test.js", registry, .{ .env = .{ .node = true } }, std.testing.allocator);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), result.diagnostics.len);
    try std.testing.expectEqualStrings("env-check", result.diagnostics[0].rule_code);
}

fn envRule(ctx: common.LintContext, rule: common.LintRule) !void {
    if (ctx.env.node) {
        if (std.mem.indexOf(u8, ctx.source, "process.exit")) |idx| {
            try ctx.report(rule.code, rule.severity, "node env enabled", idx, idx + "process.exit".len);
        }
    }
}

test "no-process-exit rule fires when env.node is true" {
    const cfg = linter.Config{ .env = .{ .node = true } };
    const result = try linter.lintWithConfig("process.exit(1)", "test.js", cfg, std.testing.allocator);
    defer result.deinit(std.testing.allocator);

    var found = false;
    for (result.diagnostics) |d| {
        if (std.mem.eql(u8, d.rule_code, "no-process-exit")) {
            try std.testing.expectEqual(linter.Severity.err, d.severity);
            found = true;
        }
    }
    try std.testing.expect(found);
}

test "no-process-exit rule does not fire when env is empty" {
    const result = try linter.lintWithDefaultRules("process.exit(1)", "test.js", std.testing.allocator);
    defer result.deinit(std.testing.allocator);

    for (result.diagnostics) |d| {
        if (std.mem.eql(u8, d.rule_code, "no-process-exit")) {
            return error.ShouldNotFire;
        }
    }
}

test "no-process-exit rule does not fire when only env.deno is true" {
    const cfg = linter.Config{ .env = .{ .deno = true } };
    const result = try linter.lintWithConfig("process.exit(1)", "test.js", cfg, std.testing.allocator);
    defer result.deinit(std.testing.allocator);

    for (result.diagnostics) |d| {
        if (std.mem.eql(u8, d.rule_code, "no-process-exit")) {
            return error.ShouldNotFire;
        }
    }
}

test "no-process-exit rule does not fire when only env.bun is true" {
    const cfg = linter.Config{ .env = .{ .bun = true } };
    const result = try linter.lintWithConfig("process.exit(1)", "test.js", cfg, std.testing.allocator);
    defer result.deinit(std.testing.allocator);

    for (result.diagnostics) |d| {
        if (std.mem.eql(u8, d.rule_code, "no-process-exit")) {
            return error.ShouldNotFire;
        }
    }
}

test "no-process-exit rule fires when env.node is true even with other envs" {
    const cfg = linter.Config{ .env = .{ .node = true, .deno = true, .bun = true } };
    const result = try linter.lintWithConfig("process.exit(1)", "test.js", cfg, std.testing.allocator);
    defer result.deinit(std.testing.allocator);

    var found = false;
    for (result.diagnostics) |d| {
        if (std.mem.eql(u8, d.rule_code, "no-process-exit")) {
            found = true;
        }
    }
    try std.testing.expect(found);
}

test "parseConfig parses tabWidth numeric value" {
    var cfg = try linter.parseConfig(
        \\export default defineConfig([{
        \\  formatter: {
        \\    tabWidth: 4,
        \\  },
        \\}])
    , std.testing.allocator);
    defer cfg.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 4), cfg.formatter.options.tabWidth);
}

test "parseConfig parses printWidth numeric value" {
    var cfg = try linter.parseConfig(
        \\export default defineConfig([{
        \\  formatter: {
        \\    printWidth: 120,
        \\  },
        \\}])
    , std.testing.allocator);
    defer cfg.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 120), cfg.formatter.options.printWidth);
}

test "parseConfig parses tabWidth from json config" {
    var cfg = try linter.parseConfig(
        \\{
        \\ "formatter": {
        \\  "tabWidth": 8,
        \\  "printWidth": 100
        \\ }
        \\}
    , std.testing.allocator);
    defer cfg.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 8), cfg.formatter.options.tabWidth);
    try std.testing.expectEqual(@as(usize, 100), cfg.formatter.options.printWidth);
}

test "parseConfig default tabWidth is 2" {
    var cfg = try linter.parseConfig(
        \\export default defineConfig([])
    , std.testing.allocator);
    defer cfg.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), cfg.formatter.options.tabWidth);
}

test "parseConfig default printWidth is 80" {
    var cfg = try linter.parseConfig(
        \\export default defineConfig([])
    , std.testing.allocator);
    defer cfg.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 80), cfg.formatter.options.printWidth);
}

test "linter.rules disables a rule" {
    var cfg = try linter.parseConfig(
        \\export default defineConfig([{
        \\  rules: {
        \\    'no-debugger': 'off',
        \\  },
        \\}])
    , std.testing.allocator);
    defer cfg.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), cfg.rule_overrides.items.len);
    try std.testing.expectEqualStrings("no-debugger", cfg.rule_overrides.items[0].code);
    try std.testing.expectEqual(false, cfg.rule_overrides.items[0].enabled);
    try std.testing.expectEqual(@as(?linter.Severity, null), cfg.rule_overrides.items[0].severity);
}

test "linter.rules changes severity" {
    var cfg = try linter.parseConfig(
        \\export default defineConfig([{
        \\  rules: {
        \\    'no-console': 'warn',
        \\  },
        \\}])
    , std.testing.allocator);
    defer cfg.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), cfg.rule_overrides.items.len);
    try std.testing.expectEqualStrings("no-console", cfg.rule_overrides.items[0].code);
    try std.testing.expectEqual(true, cfg.rule_overrides.items[0].enabled);
    try std.testing.expectEqual(linter.Severity.warn, cfg.rule_overrides.items[0].severity.?);
}

test "linter.rules off suppresses rule diagnostics" {
    var cfg = try linter.parseConfig(
        \\export default defineConfig([{
        \\  rules: {
        \\    'no-debugger': 'off',
        \\  },
        \\}])
    , std.testing.allocator);
    defer cfg.deinit(std.testing.allocator);

    const result = try linter.lintWithConfig("debugger;", "test.ts", cfg, std.testing.allocator);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
}

test "linter.rules multiple overrides" {
    var cfg = try linter.parseConfig(
        \\export default defineConfig([{
        \\  rules: {
        \\    'no-debugger': 'off',
        \\    'no-eval': 'warn',
        \\  },
        \\}])
    , std.testing.allocator);
    defer cfg.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), cfg.rule_overrides.items.len);
    const result = try linter.lintWithConfig("debugger; eval('x')", "test.ts", cfg, std.testing.allocator);
    defer result.deinit(std.testing.allocator);

    var found_eval = false;
    for (result.diagnostics) |d| {
        if (std.mem.eql(u8, d.rule_code, "no-debugger")) {
            return error.ShouldNotFire;
        }
        if (std.mem.eql(u8, d.rule_code, "no-eval")) {
            try std.testing.expectEqual(linter.Severity.warn, d.severity);
            found_eval = true;
        }
    }
    try std.testing.expect(found_eval);
}

test "no-unused-vars does not fire for exported const" {
    const result = try linter.lintWithDefaultRules("export const env = {}", "env.ts", std.testing.allocator);
    defer result.deinit(std.testing.allocator);

    for (result.diagnostics) |d| {
        if (std.mem.eql(u8, d.rule_code, "no-unused-vars")) {
            return error.ShouldNotFire;
        }
    }
}

test "no-unused-vars fires for non-exported const" {
    const result = try linter.lintWithDefaultRules("const env = {}", "env.ts", std.testing.allocator);
    defer result.deinit(std.testing.allocator);

    var found = false;
    for (result.diagnostics) |d| {
        if (std.mem.eql(u8, d.rule_code, "no-unused-vars")) {
            found = true;
        }
    }
    try std.testing.expect(found);
}

test "parseConfig supports rules with array syntax" {
    var cfg = try linter.parseConfig(
        \\export default defineConfig([{
        \\  rules: {
        \\    'formatter/quotes': ['error', 'single'],
        \\    'formatter/semi': ['error', false],
        \\  },
        \\}])
    , std.testing.allocator);
    defer cfg.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), cfg.rule_overrides.items.len);
    try std.testing.expectEqualStrings("formatter/quotes", cfg.rule_overrides.items[0].code);
    try std.testing.expectEqual(linter.Severity.err, cfg.rule_overrides.items[0].severity.?);
    try std.testing.expectEqualStrings("single", cfg.rule_overrides.items[0].option_string.?);
    try std.testing.expectEqualStrings("formatter/semi", cfg.rule_overrides.items[1].code);
    try std.testing.expectEqual(false, cfg.rule_overrides.items[1].option_bool.?);
}

test "parseConfig supports top-level rules with array syntax" {
    var cfg = try linter.parseConfig(
        \\export default defineConfig([{
        \\  rules: {
        \\    'formatter/quotes': ['warn', 'single'],
        \\  },
        \\}])
    , std.testing.allocator);
    defer cfg.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), cfg.rule_overrides.items.len);
    try std.testing.expectEqual(linter.Severity.warn, cfg.rule_overrides.items[0].severity.?);
    try std.testing.expectEqualStrings("single", cfg.rule_overrides.items[0].option_string.?);
}

test "parseConfig supports integer severity 0/1/2" {
    var cfg = try linter.parseConfig(
        \\export default defineConfig([{
        \\  rules: {
        \\    'no-debugger': 0,
        \\    'no-eval': 1,
        \\    'no-alert': 2,
        \\  },
        \\}])
    , std.testing.allocator);
    defer cfg.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), cfg.rule_overrides.items.len);
    try std.testing.expectEqual(false, cfg.rule_overrides.items[0].enabled);
    try std.testing.expectEqual(linter.Severity.warn, cfg.rule_overrides.items[1].severity.?);
    try std.testing.expectEqual(linter.Severity.err, cfg.rule_overrides.items[2].severity.?);
}

test "parseConfig deduplicates rules across multiple array items" {
    var cfg = try linter.parseConfig(
        \\export default defineConfig([{
        \\  rules: {
        \\    'no-debugger': 'off',
        \\  },
        \\}, {
        \\  rules: {
        \\    'no-debugger': 'warn',
        \\  },
        \\}])
    , std.testing.allocator);
    defer cfg.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), cfg.rule_overrides.items.len);
    try std.testing.expectEqual(false, cfg.rule_overrides.items[0].enabled);
}

test "parseFormatterConfig reads formatter section from unified config" {
    var cfg = try linter.parseFormatterConfig(
        \\export default defineConfig({
        \\ formatter: {
        \\   singleQuote: true,
        \\   semi: false,
        \\   trailingComma: 'all',
        \\   tabWidth: 4,
        \\ }
        \\})
    , std.testing.allocator);
    defer cfg.deinit(std.testing.allocator);

    try std.testing.expectEqual(true, cfg.options.singleQuote);
    try std.testing.expectEqual(false, cfg.options.semi);
    try std.testing.expectEqual(common.TrailingComma.all, cfg.options.trailingComma);
    try std.testing.expectEqual(@as(usize, 4), cfg.options.tabWidth);
}

test "unified nxc.config.js with formatter and linter" {
    var cfg = try linter.parseConfig(
        \\export default defineConfig({
        \\ formatter: {
        \\   singleQuote: true,
        \\   semi: false,
        \\ },
        \\ linter: [
        \\   {
        \\     rules: {
        \\       'formatter/quotes': ['error', 'single'],
        \\     }
        \\   },
        \\   {
        \\     rules: {
        \\       'no-debugger': 'off',
        \\       'prefer-template': 'warn',
        \\     }
        \\   }
        \\ ]
        \\})
    , std.testing.allocator);
    defer cfg.deinit(std.testing.allocator);

    try std.testing.expectEqual(true, cfg.formatter.options.singleQuote);
    try std.testing.expectEqual(false, cfg.formatter.options.semi);
    try std.testing.expectEqual(@as(usize, 3), cfg.rule_overrides.items.len);
}

test "formatter/quotes rule detects double quotes when single expected" {
    var cfg = try linter.parseConfig(
        \\export default defineConfig([{
        \\  rules: {
        \\    'formatter/quotes': ['error', 'single'],
        \\  },
        \\}])
    , std.testing.allocator);
    defer cfg.deinit(std.testing.allocator);

    const result = try linter.lintWithConfig("const x = \"hello\";", "test.ts", cfg, std.testing.allocator);
    defer result.deinit(std.testing.allocator);

    var found = false;
    for (result.diagnostics) |d| {
        if (std.mem.eql(u8, d.rule_code, "formatter/quotes")) {
            found = true;
        }
    }
    try std.testing.expect(found);
}

test "formatter/semi rule detects missing semicolons" {
    var cfg = try linter.parseConfig(
        \\export default defineConfig([{
        \\  rules: {
        \\    'formatter/semi': ['error', true],
        \\  },
        \\}])
    , std.testing.allocator);
    defer cfg.deinit(std.testing.allocator);

    const result = try linter.lintWithConfig("const x = 1", "test.ts", cfg, std.testing.allocator);
    defer result.deinit(std.testing.allocator);

    var found = false;
    for (result.diagnostics) |d| {
        if (std.mem.eql(u8, d.rule_code, "formatter/semi")) {
            found = true;
        }
    }
    try std.testing.expect(found);
}

test "lintWithConfig applies rule_overrides from config" {
    var cfg = linter.Config{
        .rule_overrides = blk: {
            var list = std.ArrayListUnmanaged(linter.RuleOverride).empty;
            list.append(std.testing.allocator, .{
                .code = try std.testing.allocator.dupe(u8, "formatter/quotes"),
                .severity = .warn,
                .option_string = try std.testing.allocator.dupe(u8, "single"),
            }) catch unreachable;
            break :blk list;
        },
    };
    defer cfg.deinit(std.testing.allocator);
    const result = try linter.lintWithConfig("const x = \"hello\";", "test.ts", cfg, std.testing.allocator);
    defer result.deinit(std.testing.allocator);

    var found = false;
    for (result.diagnostics) |d| {
        if (std.mem.eql(u8, d.rule_code, "formatter/quotes")) {
            found = true;
        }
    }
    try std.testing.expect(found);
}

test "defineConfig with env and rules" {
    var cfg = try linter.parseConfig(
        \\export default defineConfig([{
        \\  env: { node: true },
        \\  rules: {
        \\    'no-process-exit': 'off',
        \\    'prefer-template': 'warn',
        \\    'formatter/quotes': ['error', 'single'],
        \\    'formatter/semi': ['error', false],
        \\  },
        \\}])
    , std.testing.allocator);
    defer cfg.deinit(std.testing.allocator);

    try std.testing.expectEqual(true, cfg.env.node);
    try std.testing.expectEqual(@as(usize, 4), cfg.rule_overrides.items.len);
}

test "defineConfig merges rules from multiple array items" {
    var cfg = try linter.parseConfig(
        \\export default defineConfig([{
        \\  env: { node: true },
        \\  rules: {
        \\    'no-process-exit': 'off',
        \\    'prefer-template': 'warn',
        \\  },
        \\}, {
        \\  rules: {
        \\    'no-constant-condition': 'off',
        \\    'no-constant-binary-expression': 'off',
        \\  },
        \\}])
    , std.testing.allocator);
    defer cfg.deinit(std.testing.allocator);

    try std.testing.expectEqual(true, cfg.env.node);
    try std.testing.expectEqual(@as(usize, 4), cfg.rule_overrides.items.len);
}

test "defineConfig empty array returns default config" {
    var cfg = try linter.parseConfig(
        \\export default defineConfig([])
    , std.testing.allocator);
    defer cfg.deinit(std.testing.allocator);

    try std.testing.expectEqual(false, cfg.env.node);
    try std.testing.expectEqual(@as(usize, 0), cfg.rule_overrides.items.len);
}

test "parseConfig still supports plain object format" {
    var cfg = try linter.parseConfig(
        \\export default {
        \\ env: { node: true },
        \\ rules: {
        \\ 'no-debugger': 'off',
        \\ },
        \\};
    , std.testing.allocator);
    defer cfg.deinit(std.testing.allocator);

    try std.testing.expectEqual(true, cfg.env.node);
    try std.testing.expectEqual(@as(usize, 1), cfg.rule_overrides.items.len);
}

test "formatter/quotes respects singleQuote:true from formatter config" {
    var cfg = try linter.parseConfig(
        \\export default defineConfig({
        \\ formatter: { singleQuote: true },
        \\})
    , std.testing.allocator);
    defer cfg.deinit(std.testing.allocator);

    const result = try linter.lintWithConfig("const x = \"hello\";", "test.ts", cfg, std.testing.allocator);
    defer result.deinit(std.testing.allocator);

    var found = false;
    for (result.diagnostics) |d| {
        if (std.mem.eql(u8, d.rule_code, "formatter/quotes")) {
            found = true;
            try std.testing.expectEqualStrings("Strings must use single quotes", d.message);
        }
    }
    try std.testing.expect(found);
}

test "formatter/quotes allows single quotes when singleQuote:true from formatter config" {
    var cfg = try linter.parseConfig(
        \\export default defineConfig({
        \\ formatter: { singleQuote: true },
        \\})
    , std.testing.allocator);
    defer cfg.deinit(std.testing.allocator);

    const result = try linter.lintWithConfig("const x = 'hello';", "test.ts", cfg, std.testing.allocator);
    defer result.deinit(std.testing.allocator);

    for (result.diagnostics) |d| {
        if (std.mem.eql(u8, d.rule_code, "formatter/quotes")) {
            return error.ShouldNotFire;
        }
    }
}

test "formatter/quotes reports double quotes when singleQuote:false from formatter config" {
    var cfg = try linter.parseConfig(
        \\export default defineConfig({
        \\ formatter: { singleQuote: false },
        \\})
    , std.testing.allocator);
    defer cfg.deinit(std.testing.allocator);

    const result = try linter.lintWithConfig("const x = 'hello';", "test.ts", cfg, std.testing.allocator);
    defer result.deinit(std.testing.allocator);

    var found = false;
    for (result.diagnostics) |d| {
        if (std.mem.eql(u8, d.rule_code, "formatter/quotes")) {
            found = true;
            try std.testing.expectEqualStrings("Strings must use double quotes", d.message);
        }
    }
    try std.testing.expect(found);
}

