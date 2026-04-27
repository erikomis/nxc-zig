const std = @import("std");
const h = @import("harness");
const linter = @import("linter");

test "formatter package can remove semicolons" {
    const out = try linter.format("const x = 1;", .{ .semi = false }, std.testing.allocator);
    defer std.testing.allocator.free(out);

    try std.testing.expectEqualStrings("const x = 1", out);
}

test "preserves leading semicolon for async arrow IIFE" {
    const src =
        \\;(async () => {
        \\  //
        \\})()
    ;
    try h.testFormat(src, .{}, src);
}

test "preserves leading semicolon for function IIFE" {
    const src =
        \\;(function () {
        \\  //
        \\})()
    ;
    try h.testFormat(src, .{}, src);
}

test "preserves leading semicolon for async function IIFE" {
    const src =
        \\;(async function () {
        \\  //
        \\})()
    ;
    try h.testFormat(src, .{}, src);
}

test "preserves leading semicolon for array expression" {
    const src = ";[1, 2, 3].forEach(() => {})";
    try h.testFormat(src, .{}, src);
}

test "preserves leading semicolon for array expression (multiline call)" {
    const src =
        \\;[1, 2, 3].forEach((x) => {
        \\  console.log(x);
        \\})
    ;
    try h.testFormat(src, .{}, src);
}

test "preserves leading semicolon for template literal" {
    const src = ";`test`";
    try h.testFormat(src, .{}, src);
}

test "preserves leading semicolon for tagged template" {
    const src = ";tag`test`";
    try h.testFormat(src, .{}, src);
}

test "preserves leading semicolon with idempotency for async IIFE" {
    const src =
        \\;(async () => {
        \\  //
        \\})()
    ;
    try h.testIdempotent(src, .{});
}

test "preserves leading semicolon for function IIFE with idempotency" {
    const src =
        \\;(function () {
        \\  //
        \\})()
    ;
    try h.testIdempotent(src, .{});
}

test "preserves leading semicolon for array expression idempotent" {
    const src = ";[1, 2, 3].forEach(() => {})";
    try h.testIdempotent(src, .{});
}

test "preserves leading semicolon for template literal idempotent" {
    const src = ";`test`";
    try h.testIdempotent(src, .{});
}

test "does not add semicolon for normal empty statement" {
    const src = "const x = 1; ; const y = 2;";
    const expected = "const x = 1;\nconst y = 2;";
    try h.testFormat(src, .{}, expected);
}

test "leading semicolon not added when empty_stmt not followed by ASI-sensitive expr" {
    const src =
        \\;
        \\const x = 1;
    ;
    const expected = "const x = 1;";
    try h.testFormat(src, .{}, expected);
}

test "leading semicolon preserved with semi: false option" {
    const src = ";[1, 2, 3].forEach(() => {})";
    const expected = ";[1, 2, 3].forEach(() => {})";
    try h.testFormat(src, .{ .semi = false }, expected);
}

test "leading semicolon preserved for IIFE with semi: false option" {
    const src =
        \\;(async () => {
        \\  //
        \\})()
    ;
    try h.testFormat(src, .{ .semi = false }, src);
}

test "multiline safety preserves leading semicolon after var decl" {
    const src =
        \\const foo = bar
        \\.(async () => {})()
    ;
    // The ; should be preserved on its own line, not attached to the var decl
    try h.testFormat(src, .{}, src);
}

test "multiline safety with semi false" {
    const src =
        \\const foo = bar
        \\.(async () => {})()
    ;
    // Defensive ; must be preserved even with semi: false
    try h.testFormat(src, .{ .semi = false }, src);
}

test "multiline safety with array expression" {
    const src =
        \\const x = y
        \\;[1, 2, 3].forEach(() => {})
    ;
    try h.testFormat(src, .{}, src);
}

test "multiline safety with template literal" {
    const src =
        \\const x = y
        \\;`template`
    ;
    try h.testFormat(src, .{}, src);
}
