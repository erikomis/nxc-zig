const std = @import("std");
const h = @import("harness");
const linter = @import("linter");

test "formatter package formats source with options" {
    const out = try linter.format("const x = 'a'", .{ .singleQuote = false, .semi = true }, std.testing.allocator);
    defer std.testing.allocator.free(out);

    try std.testing.expectEqualStrings("const x = \"a\";", out);
}

test "formatter package supports prettier-like options" {
    const out = try linter.format(
        "  const value = { name: 'ana' };\n  const other = [ 1 ];",
        .{
            .singleQuote = true,
            .trailingComma = .none,
            .bracketSpacing = false,
            .semi = false,
            .printWidth = 80,
            .quoteProps = .consistent,
            .proseWrap = .preserve,
            .arrowParens = .always,
            .bracketSameLine = true,
            .endOfLine = .lf,
            .singleAttributePerLine = false,
            .jsxSingleQuote = false,
            .useTabs = false,
            .tabWidth = 2,
            .plugins = &.{},
        },
        std.testing.allocator,
    );
    defer std.testing.allocator.free(out);

    try std.testing.expectEqualStrings("const value = {name: 'ana'}\nconst other = [1]", out);
}

test "formatter applies bracketSpacing false to object literals" {
    const out = try linter.format("const user = { name: 'Joao', age: 20 };", .{ .singleQuote = true, .bracketSpacing = false, .semi = true }, std.testing.allocator);
    defer std.testing.allocator.free(out);

    try std.testing.expectEqualStrings("const user = {name: 'Joao', age: 20};", out);
}

test "formatter applies bracketSpacing true with preserved quoted keys" {
    const out = try linter.format("const obj = {'name': 'John Joe', age: 35}", .{ .singleQuote = true, .quoteProps = .preserve, .bracketSpacing = true, .semi = false }, std.testing.allocator);
    defer std.testing.allocator.free(out);

    try std.testing.expectEqualStrings("const obj = { 'name': 'John Joe', age: 35 }", out);
}

test "formatter applies bracketSpacing false with preserved quoted keys" {
    const out = try linter.format("const obj = {'name': 'John Joe', age: 35}", .{ .singleQuote = true, .quoteProps = .preserve, .bracketSpacing = false, .semi = false }, std.testing.allocator);
    defer std.testing.allocator.free(out);

    try std.testing.expectEqualStrings("const obj = {'name': 'John Joe', age: 35}", out);
}

test "formatter applies quoteProps consistent to object literals" {
    const out = try linter.format("const user = { foo: 1, 'bar-baz': 2 };", .{ .singleQuote = true, .quoteProps = .consistent, .semi = true }, std.testing.allocator);
    defer std.testing.allocator.free(out);

    try std.testing.expectEqualStrings("const user = { 'foo': 1, 'bar-baz': 2 };", out);
}

test "formatter keeps as-needed object property quotes minimal" {
    const out = try linter.format("const user = { 'foo': 1, bar: 2 };", .{ .singleQuote = true, .quoteProps = .as_needed, .semi = true }, std.testing.allocator);
    defer std.testing.allocator.free(out);

    try std.testing.expectEqualStrings("const user = { foo: 1, bar: 2 };", out);
}
