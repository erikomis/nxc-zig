const std = @import("std");
const h = @import("harness");
const linter = @import("linter");

test "formatter preserves inline block comments like prettier" {
    const source = "foo( /*a*/ bar)";
    const out = try linter.format(source, .{ .semi = true }, std.testing.allocator);
    defer std.testing.allocator.free(out);

    try std.testing.expectEqualStrings("foo( /*a*/ bar);", out);
}

test "formatter preserves block comments before statements" {
    const source =
        \\if (true) { /*a
        \\ b*/ foo(); }
    ;
    const out = try linter.format(source, .{ .semi = true }, std.testing.allocator);
    defer std.testing.allocator.free(out);

    try std.testing.expectEqualStrings(
        \\if (true) { /*a
        \\ b*/ foo();
        \\}
    , out);
}

test "formatter preserves inline line comments in binary expressions" {
    const source =
        \\const value = foo + // a
        \\bar;
    ;
    const out = try linter.format(source, .{ .semi = true }, std.testing.allocator);
    defer std.testing.allocator.free(out);

    try std.testing.expectEqualStrings(
        \\const value = foo + // a
        \\bar;
    , out);
}

test "formatter keeps block comment before closing brace inside block" {
    const source =
        \\function bootstrap() {
        \\  const name = 'John'  /* dummy */
        \\  console.log(`Welcome, ` + name)
        \\  /* dummy */
        \\}
        \\bootstrap()
    ;
    const out = try linter.format(source, .{ .semi = true }, std.testing.allocator);
    defer std.testing.allocator.free(out);

    try std.testing.expectEqualStrings(
        \\function bootstrap() {
        \\  const name = "John"; /* dummy */
        \\  console.log(`Welcome, ` + name);
        \\  /* dummy */
        \\}
        \\bootstrap();
    , out);
}

test "formatter keeps trailing block comment attached to last statement in block" {
    const source =
        \\if (flag) {
        \\  work() /* keep */
        \\}
    ;
    const out = try linter.format(source, .{ .semi = true }, std.testing.allocator);
    defer std.testing.allocator.free(out);

    try std.testing.expectEqualStrings(
        \\if (flag) {
        \\  work(); /* keep */
        \\}
    , out);
}

test "formatter keeps comment before closing brace in user repro" {
    const source =
        \\function bootstrap() {
        \\  const name = 'John'  /* dummy */
        \\  console.log(`Welcome, ` + name)
        \\  /* dummy */
        \\}
        \\bootstrap()
    ;
    const out = try linter.format(source, .{ .semi = false }, std.testing.allocator);
    defer std.testing.allocator.free(out);

    try std.testing.expectEqualStrings(
        \\function bootstrap() {
        \\  const name = "John" /* dummy */
        \\  console.log(`Welcome, ` + name)
        \\  /* dummy */
        \\}
        \\bootstrap()
    , out);
}

test "formatter keeps trailing block comment on same line" {
    const out = try linter.format(
        "function bootstrap() {\n  const name = 'John' /* dummy */\n  console.log(name)\n}",
        .{ .singleQuote = true, .semi = false },
        std.testing.allocator,
    );
    defer std.testing.allocator.free(out);

    try std.testing.expectEqualStrings(
        \\function bootstrap() {
        \\  const name = 'John' /* dummy */
        \\  console.log(name)
        \\}
    , out);
}

test "formatter preserves blank lines between top level statements" {
    const source =
        \\const obj = { name: 'Luciano', age: 27 }
        \\
        \\const sum = (v: number) => v * 4
        \\
        \\const arr = [10, 20, 30]
        \\
        \\const newArr = arr.map((x: number) => x * 4)
    ;
    const out = try linter.format(source, .{ .singleQuote = true, .semi = false, .arrowParens = .always }, std.testing.allocator);
    defer std.testing.allocator.free(out);

    try std.testing.expectEqualStrings(source, out);
}

test "formatter preserverves empty lines and comments inside blocks" {
    const source =
        \\function bootstrap() {
        \\  /* dummy */
        \\  const name = 'John'
        \\  console.log(`Welcome, ` + name)
        \\  /* dummny */
        \\}
        \\
        \\bootstrap()
    ;
    const out = try linter.format(source, .{ .singleQuote = true, .semi = false }, std.testing.allocator);
    defer std.testing.allocator.free(out);

    try std.testing.expectEqualStrings(source, out);
}

test "formatter preserves blank lines between block statements" {
    const source =
        \\function demo() {
        \\  const a = 1
        \\
        \\  const b = 2
        \\
        \\  const c = a + b
        \\}
    ;
    const out = try linter.format(source, .{ .singleQuote = true, .semi = false }, std.testing.allocator);
    defer std.testing.allocator.free(out);

    try std.testing.expectEqualStrings(source, out);
}
