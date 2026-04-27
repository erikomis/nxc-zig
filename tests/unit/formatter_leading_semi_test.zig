const std = @import("std");
const linter = @import("linter");

test "formatter: preserves leading semicolon for async arrow IIFE" {
    const src =
        \\;(async () => {
        \\  //
        \\})()
    ;
    const out = try linter.format(src, .{}, std.testing.allocator);
    defer std.testing.allocator.free(out);
    const expected =
        \\;(async () => {
        \\  //
        \\})();
    ;
    try std.testing.expectEqualStrings(expected, out);
}

test "formatter: preserves leading semicolon for function IIFE" {
    const src =
        \\;(function () {
        \\  //
        \\})()
    ;
    const out = try linter.format(src, .{}, std.testing.allocator);
    defer std.testing.allocator.free(out);
    const expected =
        \\;(function() {
        \\  //
        \\})();
    ;
    try std.testing.expectEqualStrings(expected, out);
}

test "formatter: preserves leading semicolon for array expression" {
    const src = ";[1, 2, 3].forEach(() => {})";
    const out = try linter.format(src, .{}, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(";[1, 2, 3].forEach(() => {});", out);
}

test "formatter: preserves leading semicolon for array literal" {
    const src = ";[1, 2, 3]";
    const out = try linter.format(src, .{}, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(";[1, 2, 3];", out);
}

test "formatter: preserves leading semicolon with semi:false" {
    const src = ";[1, 2, 3].forEach(() => {})";
    const out = try linter.format(src, .{ .semi = false }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(";[1, 2, 3].forEach(() => {})", out);
}

test "formatter: preserves leading semicolon for IIFE with semi:false" {
    const src =
        \\;(async () => {
        \\  //
        \\})()
    ;
    const out = try linter.format(src, .{ .semi = false }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(
        \\;(async () => {
        \\  //
        \\})()
    , out);
}

test "formatter: preserves leading semicolon after var decl" {
    const src =
        \\const foo = bar
        \\.(async () => {})()
    ;
    const out = try linter.format(src, .{}, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(
        \\const foo = bar;
        \\.(async () => {})();
    , out);
}

test "formatter: preserves leading semicolon after var decl with semi:false" {
    const src =
        \\const foo = bar
        \\.(async () => {})()
    ;
    const out = try linter.format(src, .{ .semi = false }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(
        \\const foo = bar
        \\.(async () => {})()
    , out);
}

test "formatter: idempotent with leading semicolon IIFE" {
    const src =
        \\;(async () => {
        \\  //
        \\})()
    ;
    const out1 = try linter.format(src, .{}, std.testing.allocator);
    defer std.testing.allocator.free(out1);
    const out2 = try linter.format(out1, .{}, std.testing.allocator);
    defer std.testing.allocator.free(out2);
    try std.testing.expectEqualStrings(out1, out2);
}

test "formatter: idempotent with leading semicolon array" {
    const src = ";[1, 2, 3].forEach(() => {})";
    const out1 = try linter.format(src, .{}, std.testing.allocator);
    defer std.testing.allocator.free(out1);
    const out2 = try linter.format(out1, .{}, std.testing.allocator);
    defer std.testing.allocator.free(out2);
    try std.testing.expectEqualStrings(out1, out2);
}

test "formatter: does not add leading semicolon for non-ASI-sensitive expr" {
    const src =
        \\;
        \\const x = 1;
    ;
    const out = try linter.format(src, .{}, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expect(out[0] != ';');
    try std.testing.expect(out.len > 0);
}

test "formatter: does not break normal semicolons" {
    const src = "const x = 1;";
    const out = try linter.format(src, .{}, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("const x = 1;", out);
}

test "formatter: leading semicolon stays on same line as IIFE" {
    const src = ";(async () => {})()";
    const out = try linter.format(src, .{}, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(";(async () => {})();", out);
}
