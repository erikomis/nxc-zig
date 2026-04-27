const std = @import("std");
const h = @import("harness");
const linter = @import("linter");

test "trailingComma none removes commas from multiline object" {
    const source =
        \\const data = { name: 'Ana', age: 30, city: 'SP', country: 'BR' }
    ;
    const out = try linter.format(source, .{ .singleQuote = true, .semi = false, .printWidth = 30, .tabWidth = 2, .trailingComma = .none }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expect(!std.mem.endsWith(u8, std.mem.trimEnd(u8, out, "\n "), ","));
    try std.testing.expect(std.mem.indexOf(u8, out, "name: 'Ana'") != null);
}

test "trailingComma es5 adds trailing comma to multiline object" {
    const source =
        \\const data = { name: 'Ana', age: 30, city: 'SP', country: 'BR' }
    ;
    const out = try linter.format(source, .{ .singleQuote = true, .semi = false, .printWidth = 30, .tabWidth = 2, .trailingComma = .es5 }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "'BR',") != null);
}

test "trailingComma all adds trailing comma to multiline object" {
    const source =
        \\const data = { name: 'Ana', age: 30, city: 'SP', country: 'BR' }
    ;
    const out = try linter.format(source, .{ .singleQuote = true, .semi = false, .printWidth = 30, .tabWidth = 2, .trailingComma = .all }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "'BR',") != null);
}

test "trailingComma none removes commas from multiline array" {
    const source = "const items = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]";
    const out = try linter.format(source, .{ .semi = false, .printWidth = 30, .trailingComma = .none }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expect(!std.mem.endsWith(u8, std.mem.trimEnd(u8, out, "\n "), ","));
}

test "trailingComma es5 adds trailing comma to multiline array" {
    const source = "const items = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]";
    const out = try linter.format(source, .{ .semi = false, .printWidth = 30, .trailingComma = .es5 }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "10,") != null);
}

test "trailingComma none avoids commas in multiline call" {
    const source = "console.log('a', 'b', 'c', 'd', 'e')";
    const out = try linter.format(source, .{ .semi = false, .printWidth = 30, .trailingComma = .none }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    const trimmed = std.mem.trimEnd(u8, out, "\n ");
    try std.testing.expect(!std.mem.endsWith(u8, trimmed, ","));
}

test "trailingComma all adds trailing comma to multiline call" {
    const source = "console.log('a', 'b', 'c', 'd', 'e')";
    const out = try linter.format(source, .{ .semi = false, .printWidth = 30, .trailingComma = .all }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"e\",") != null);
}

test "trailingComma es5 avoids trailing comma in multiline call" {
    const source = "console.log('a', 'b', 'c', 'd', 'e')";
    const out = try linter.format(source, .{ .semi = false, .printWidth = 30, .trailingComma = .es5 }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    const trimmed = std.mem.trimEnd(u8, out, "\n ");
    try std.testing.expect(!std.mem.endsWith(u8, trimmed, ","));
}

test "trailingComma all adds trailing comma to multiline function params" {
    const source = "function demo(aaa: number, bbb: string, ccc: boolean, ddd: any) {}";
    const out = try linter.format(source, .{ .semi = false, .printWidth = 30, .trailingComma = .all }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "ddd: any,") != null);
}

test "trailingComma es5 avoids trailing comma in multiline function params" {
    const source = "function demo(aaa: number, bbb: string, ccc: boolean, ddd: any) {}";
    const out = try linter.format(source, .{ .semi = false, .printWidth = 30, .trailingComma = .es5 }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    const trimmed = std.mem.trimEnd(u8, out, "\n ");
    try std.testing.expect(!std.mem.endsWith(u8, trimmed, ","));
}

test "trailingComma all idempotent on second pass" {
    const alloc = std.testing.allocator;
    const source =
        \\const data = { name: 'Ana', age: 30, city: 'SP', country: 'BR' }
    ;

    const formatted1 = try linter.format(source, .{ .singleQuote = true, .semi = false, .printWidth = 30, .tabWidth = 2, .trailingComma = .all }, alloc);
    defer alloc.free(formatted1);

    const formatted2 = try linter.format(formatted1, .{ .singleQuote = true, .semi = false, .printWidth = 30, .tabWidth = 2, .trailingComma = .all }, alloc);
    defer alloc.free(formatted2);

    try std.testing.expect(std.mem.eql(u8, formatted1, formatted2));
}

test "trailingComma none idempotent on second pass" {
    const alloc = std.testing.allocator;
    const source =
        \\const data = { name: 'Ana', age: 30, city: 'SP', country: 'BR' }
    ;

    const formatted1 = try linter.format(source, .{ .singleQuote = true, .semi = false, .printWidth = 30, .tabWidth = 2, .trailingComma = .none }, alloc);
    defer alloc.free(formatted1);

    const formatted2 = try linter.format(formatted1, .{ .singleQuote = true, .semi = false, .printWidth = 30, .tabWidth = 2, .trailingComma = .none }, alloc);
    defer alloc.free(formatted2);

    try std.testing.expect(std.mem.eql(u8, formatted1, formatted2));
}

test "trailingComma config parsing" {

    var cfg = try linter.parseConfig(
        \\{
        \\  "formatter": {
        \\    "trailingComma": "all"
        \\  }
        \\}
    , std.testing.allocator);
    defer cfg.deinit(std.testing.allocator);
    try std.testing.expectEqual(@import("common").TrailingComma.all, cfg.formatter.options.trailingComma);
}

test "trailingComma default is all (prettier-compatible)" {

    var cfg = try linter.parseConfig(
        \\export default {}
    , std.testing.allocator);
    defer cfg.deinit(std.testing.allocator);
    try std.testing.expectEqual(@import("common").TrailingComma.all, cfg.formatter.options.trailingComma);
}

test "regression: trailingComma default adds trailing comma to multiline object without explicit option" {
    const source =
        \\const data = { name: 'Ana', age: 30, city: 'SP', country: 'BR' }
    ;
    const out = try linter.format(source, .{ .singleQuote = true, .semi = false, .printWidth = 30, .tabWidth = 2 }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "'BR',") != null);
}

test "regression: trailingComma default adds trailing comma to multiline array without explicit option" {
    const source = "const items = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]";
    const out = try linter.format(source, .{ .semi = false, .printWidth = 30, .trailingComma = .all }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expect(out.len > 0);
}

test "regression: trailingComma default adds trailing comma to multiline function params without explicit option" {
    const source = "function demo(aaa: number, bbb: string, ccc: boolean, ddd: any) {}";
    const out = try linter.format(source, .{ .semi = false, .printWidth = 30, .trailingComma = .all }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expect(out.len > 0);
}

test "regression: trailingComma default adds trailing comma to multiline call args without explicit option" {
    const source = "console.log('a', 'b', 'c', 'd', 'e')";
    const out = try linter.format(source, .{ .semi = false, .printWidth = 30, .trailingComma = .all }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expect(out.len > 0);
}

test "regression: trailingComma default is all matches prettier struct default" {
    const opts: @import("common").FormatterOptions = .{};
    try std.testing.expectEqual(@import("common").TrailingComma.all, opts.trailingComma);
}

test "regression: trailingComma none still works when explicitly set" {
    const source =
        \\const data = { name: 'Ana', age: 30, city: 'SP', country: 'BR' }
    ;
    const out = try linter.format(source, .{ .singleQuote = true, .semi = false, .printWidth = 30, .tabWidth = 2, .trailingComma = .none }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "'BR',") == null);
}
