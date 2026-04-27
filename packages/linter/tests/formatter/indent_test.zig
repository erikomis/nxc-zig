const std = @import("std");
const h = @import("harness");
const linter = @import("linter");

test "formatter adds indentation to unindented code" {
    const source =
        \\function shutdown() {
        \\console.log('closing server')
        \\process.exit(1)
        \\}
    ;
    const out = try linter.format(source, .{ .tabWidth = 2, .semi = false }, std.testing.allocator);
    defer std.testing.allocator.free(out);

    try std.testing.expectEqualStrings(
        \\function shutdown() {
        \\  console.log("closing server")
        \\  process.exit(1)
        \\}
    , out);
}

test "formatter respects tabWidth 4" {
    const source =
        \\function a() {
        \\if (b) {
        \\console.log("deep")
        \\}
        \\}
    ;
    const out = try linter.format(source, .{ .tabWidth = 4, .semi = false }, std.testing.allocator);
    defer std.testing.allocator.free(out);

    try std.testing.expectEqualStrings(
        \\function a() {
        \\    if (b) {
        \\        console.log("deep")
        \\    }
        \\}
    , out);
}

test "formatter respects tabWidth 8" {
    const source =
        \\function a() {
        \\console.log("x")
        \\}
    ;
    const out = try linter.format(source, .{ .tabWidth = 8, .semi = false }, std.testing.allocator);
    defer std.testing.allocator.free(out);

    try std.testing.expectEqualStrings(
        \\function a() {
        \\        console.log("x")
        \\}
    , out);
}

test "formatter uses tabs when useTabs is true" {
    const source =
        \\function a() {
        \\if (b) {
        \\console.log("deep")
        \\}
        \\}
    ;
    const out = try linter.format(source, .{ .useTabs = true, .semi = false }, std.testing.allocator);
    defer std.testing.allocator.free(out);

    try std.testing.expectEqualStrings("function a() {\n\tif (b) {\n\t\tconsole.log(\"deep\")\n\t}\n}", out);
}

test "formatter handles deep nesting" {
    const source =
        \\function a() {
        \\if (b) {
        \\for (;;) {
        \\while (c) {
        \\console.log("deep")
        \\}
        \\}
        \\}
        \\}
    ;
    const out = try linter.format(source, .{ .tabWidth = 2, .semi = false }, std.testing.allocator);
    defer std.testing.allocator.free(out);

    try std.testing.expectEqualStrings(
        \\function a() {
        \\  if (b) {
        \\    for (;;) {
        \\      while (c) {
        \\        console.log("deep")
        \\      }
        \\    }
        \\  }
        \\}
    , out);
}

test "formatter preserves existing indentation from source" {
    const source =
        \\  const value = { name: 'ana' };
        \\  const other = [ 1 ];
    ;
    const out = try linter.format(source, .{ .singleQuote = true, .bracketSpacing = false, .semi = false, .tabWidth = 2 }, std.testing.allocator);
    defer std.testing.allocator.free(out);

    try std.testing.expectEqualStrings(
        \\const value = {name: 'ana'}
        \\const other = [1]
    , out);
}

test "formatter indents content before closing brace on same line" {
    const source =
        \\function shutdown() {console.log('closing server')
        \\process.exit(1)}
    ;
    const out = try linter.format(source, .{ .tabWidth = 2, .semi = true }, std.testing.allocator);
    defer std.testing.allocator.free(out);

    try std.testing.expectEqualStrings(
        \\function shutdown() {
        \\  console.log("closing server");
        \\  process.exit(1);
        \\}
    , out);
}

test "formatter indents content before closing brace preserves existing indent" {
    const source =
        \\if (a) {
        \\foo(); }
        \\bar();
    ;
    const out = try linter.format(source, .{ .tabWidth = 2, .semi = true }, std.testing.allocator);
    defer std.testing.allocator.free(out);

    try std.testing.expectEqualStrings(
        \\if (a) {
        \\  foo();
        \\}
        \\bar();
    , out);
}

test "formatter handles empty lines" {
    const source =
        \\function a() {
        \\console.log("x")
        \\
        \\console.log("y")
        \\}
    ;
    const out = try linter.format(source, .{ .tabWidth = 2, .semi = false }, std.testing.allocator);
    defer std.testing.allocator.free(out);

    try std.testing.expectEqualStrings(
        \\function a() {
        \\  console.log("x")
        \\
        \\  console.log("y")
        \\}
    , out);
}
