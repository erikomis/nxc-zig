const std = @import("std");
const compiler = @import("compiler");
const linter = @import("linter");

test "diff simple expression" {
    const alloc = std.testing.allocator;
    const source = "console.log(42);";
    const cfg = compiler.Config{ .parser = .{ .syntax = .ecmascript }, .jsx = false, .check = false };
    const result = try compiler.compile(source, "diff_test.js", cfg, std.testing.io, alloc);
    defer result.deinit(alloc);

    try std.testing.expect(std.mem.indexOf(u8, result.code, "42") != null);
}

test "diff arrow function" {
    const alloc = std.testing.allocator;
    const source = "const add = (a, b) => a + b; console.log(add(3, 4));";
    const cfg = compiler.Config{ .parser = .{ .syntax = .ecmascript }, .jsx = false, .check = false };
    const result = try compiler.compile(source, "diff_test.js", cfg, std.testing.io, alloc);
    defer result.deinit(alloc);

    try std.testing.expect(std.mem.indexOf(u8, result.code, "add") != null);
}

test "diff class definition" {
    const alloc = std.testing.allocator;
    const source =
        \\class Foo { bar() { return "baz"; } }
        \\const f = new Foo();
        \\console.log(f.bar());
    ;
    const cfg = compiler.Config{ .parser = .{ .syntax = .ecmascript }, .jsx = false, .check = false };
    const result = try compiler.compile(source, "diff_test.js", cfg, std.testing.io, alloc);
    defer result.deinit(alloc);

    try std.testing.expect(std.mem.indexOf(u8, result.code, "class Foo") != null);
}

test "diff formatter output stable" {
    const alloc = std.testing.allocator;
    const source =
        \\function hello() {
        \\const x = 1;
        \\return x;
        \\}
    ;

    const formatted1 = try linter.format(source, .{}, alloc);
    defer alloc.free(formatted1);

    const formatted2 = try linter.format(formatted1, .{}, alloc);
    defer alloc.free(formatted2);

    try std.testing.expect(std.mem.eql(u8, formatted1, formatted2));
}

test "diff compiler and formatter roundtrip" {
    const alloc = std.testing.allocator;
    const source =
        \\function    greet(  name  )  {
        \\return  "Hello, "  +  name;
        \\}
        \\console.log(greet("World"));
    ;
    const cfg = compiler.Config{ .parser = .{ .syntax = .ecmascript }, .jsx = false, .check = false };

    const result = try compiler.compile(source, "diff_rt.js", cfg, std.testing.io, alloc);
    defer result.deinit(alloc);

    const formatted = try linter.format(source, .{}, alloc);
    defer alloc.free(formatted);

    try std.testing.expect(result.code.len > 0);
    try std.testing.expect(formatted.len > 0);

    try std.testing.expect(std.mem.indexOf(u8, formatted, "return") != null);
}
