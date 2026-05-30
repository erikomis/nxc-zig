const std = @import("std");
const h = @import("harness");
const linter = @import("linter");

test "endOfLine lf outputs lf line endings" {
    const source = "const a = 1\nconst b = 2\n";
    const out = try linter.format(source, .{ .semi = true, .endOfLine = .lf }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "\r\n") == null);
    try std.testing.expect(std.mem.count(u8, out, "\n") == 1);
}

test "endOfLine crlf outputs crlf line endings" {
    const source = "const a = 1\nconst b = 2\n";
    const out = try linter.format(source, .{ .semi = true, .endOfLine = .crlf }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "\r\n") != null);
    try std.testing.expect(std.mem.count(u8, out, "\r\n") == 1);
}

test "endOfLine cr outputs cr line endings" {
    const source = "const a = 1\nconst b = 2\n";
    const out = try linter.format(source, .{ .semi = true, .endOfLine = .cr }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.count(u8, out, "\r") == 1);
    try std.testing.expect(std.mem.indexOf(u8, out, "\n") == null);
}

test "endOfLine auto outputs lf line endings" {
    const source = "const a = 1\nconst b = 2\n";
    const out = try linter.format(source, .{ .semi = true, .endOfLine = .auto }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "\r\n") == null);
    try std.testing.expect(std.mem.count(u8, out, "\n") == 1);
}

test "endOfLine crlf multiline object has crlf" {
    const source =
        \\const data = { name: 'Ana', age: 30, city: 'SP', country: 'BR' }
    ;
    const out = try linter.format(source, .{ .singleQuote = true, .semi = false, .printWidth = 30, .tabWidth = 2, .endOfLine = .crlf }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "\r\n") != null);
}

test "endOfLine crlf idempotent on second pass" {
    const alloc = std.testing.allocator;
    const source =
        \\const a = 1
        \\const b = 2
    ;
    const formatted1 = try linter.format(source, .{ .semi = true, .endOfLine = .crlf }, alloc);
    defer alloc.free(formatted1);

    const formatted2 = try linter.format(formatted1, .{ .semi = true, .endOfLine = .crlf }, alloc);
    defer alloc.free(formatted2);

    try std.testing.expect(std.mem.eql(u8, formatted1, formatted2));
    try std.testing.expect(std.mem.count(u8, formatted1, "\r\n") == 1);
}

test "endOfLine crlf source trailing newline preserved as crlf" {
    const alloc = std.testing.allocator;
    const source = "const a = 1\nconst b = 2\n";
    const formatted = try linter.format(source, .{ .semi = true, .endOfLine = .crlf }, alloc);
    defer alloc.free(formatted);
    try std.testing.expect(std.mem.count(u8, formatted, "\r\n") == 1);
}

test "endOfLine crlf from crlf source trailing newline preserved" {
    const alloc = std.testing.allocator;
    const source = "const a = 1\r\nconst b = 2\r\n";
    const formatted = try linter.format(source, .{ .semi = true, .endOfLine = .crlf }, alloc);
    defer alloc.free(formatted);
    try std.testing.expect(std.mem.count(u8, formatted, "\r\n") == 1);
}

test "endOfLine config parsing" {

    var cfg = try linter.parseConfig(
        \\{
        \\  "formatter": {
        \\    "endOfLine": "crlf"
        \\  }
        \\}
    , std.testing.allocator);
    defer cfg.deinit(std.testing.allocator);
    try std.testing.expectEqual(@import("common").EndOfLine.crlf, cfg.formatter.options.endOfLine);
}

test "endOfLine default is lf" {

    var cfg = try linter.parseConfig(
        \\export default {}
    , std.testing.allocator);
    defer cfg.deinit(std.testing.allocator);
    try std.testing.expectEqual(@import("common").EndOfLine.lf, cfg.formatter.options.endOfLine);
}
