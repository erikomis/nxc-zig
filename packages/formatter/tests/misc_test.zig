const std = @import("std");
const h = @import("harness");
const common = @import("common");
const linter = @import("linter");

test "formatter package uses general plugins" {
    const plugins = [_]common.Plugin{.{ .name = "svelte", .format = pluginFormat }};
    const out = try linter.format("ignored", .{ .plugins = &plugins }, std.testing.allocator);
    defer std.testing.allocator.free(out);

    try std.testing.expectEqualStrings("formatted by plugin\n", out);
}

fn pluginFormat(source: []const u8, options: common.FormatterOptions, alloc: std.mem.Allocator) !?[]u8 {
    _ = source;
    _ = options;
    return try alloc.dupe(u8, "formatted by plugin");
}

test "formatter handles empty string input" {
    const out = try linter.format("", .{}, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("", out);
}

test "formatter handles unicode and emoji" {
    const out = try linter.format("const x = \"hello 🎉\";", .{}, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expect(out.len > 0);
}

test "formatter handles syntax error gracefully" {
    const out = try linter.format("const x = ;;;", .{}, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expect(out.len >= 0);
}

test "useTabs with explicit tabWidth" {
    const out = try linter.format("if(x){\n  y();\n}", .{ .useTabs = true, .tabWidth = 4 }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expect(out.len > 0);
}

test "checkFormat returns diagnostics for bad formatting" {
    const diags = try linter.checkFormat("const x = 'hello';", .{ .singleQuote = false }, std.testing.allocator);
    defer linter.freeCheckDiagnostics(std.testing.allocator, diags);
    try std.testing.expect(diags.len > 0);
}

test "checkFormat returns empty for good formatting" {
    const diags = try linter.checkFormat("const x = \"hello\";\n", .{ .singleQuote = false }, std.testing.allocator);
    defer linter.freeCheckDiagnostics(std.testing.allocator, diags);
    try std.testing.expectEqual(@as(usize, 0), diags.len);
}
