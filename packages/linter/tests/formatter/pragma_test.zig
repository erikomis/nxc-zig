const std = @import("std");
const h = @import("harness");
const linter = @import("linter");

test "checkIgnorePragma returns source unchanged when @noprettier present" {
    const source =
        \\/** @noprettier */
        \\const x = 1;
    ;
    const out = try linter.format(source, .{ .semi = true, .checkIgnorePragma = true }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(source, out);
}

test "checkIgnorePragma returns source unchanged when @noformat present" {
    const source =
        \\/** @noformat */
        \\const x = 1;
    ;
    const out = try linter.format(source, .{ .semi = true, .checkIgnorePragma = true }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(source, out);
}

test "checkIgnorePragma false formats normally" {
    const source =
        \\/** @noprettier */
        \\const x = 1
    ;
    const out = try linter.format(source, .{ .semi = true, .checkIgnorePragma = false }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(
        \\/** @noprettier */
        \\const x = 1;
    , out);
}

test "checkIgnorePragma respects shebang before pragma" {
    const source =
        \\#!/usr/bin/env node
        \\/** @noprettier */
        \\const x = 1;
    ;
    const out = try linter.format(source, .{ .semi = true, .checkIgnorePragma = true }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(source, out);
}

test "requirePragma formats when @prettier present" {
    const source =
        \\/** @prettier */
        \\const x = 1
    ;
    const out = try linter.format(source, .{ .semi = true, .requirePragma = true }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(
        \\/** @prettier */
        \\const x = 1;
    , out);
}

test "requirePragma formats when @format present" {
    const source =
        \\/** @format */
        \\const x = 1
    ;
    const out = try linter.format(source, .{ .semi = true, .requirePragma = true }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(
        \\/** @format */
        \\const x = 1;
    , out);
}

test "requirePragma returns source unchanged when pragma missing" {
    const source =
        \\const x = 1
    ;
    const out = try linter.format(source, .{ .semi = true, .requirePragma = true }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(source, out);
}

test "requirePragma false formats without pragma" {
    const source =
        \\const x = 1
    ;
    const out = try linter.format(source, .{ .semi = true, .requirePragma = false }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("const x = 1;", out);
}

test "insertPragma adds @format pragma at top" {
    const source =
        \\const x = 1
    ;
    const out = try linter.format(source, .{ .semi = true, .insertPragma = true }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.startsWith(u8, out, "/** @format */"));
    try std.testing.expect(std.mem.indexOf(u8, out, "const x = 1;") != null);
}

test "insertPragma adds after shebang" {
    const source =
        \\#!/usr/bin/env node
        \\const x = 1
    ;
    const out = try linter.format(source, .{ .semi = true, .insertPragma = true }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.startsWith(u8, out, "#!/usr/bin/env node\n/** @format */"));
    try std.testing.expect(std.mem.indexOf(u8, out, "const x = 1;") != null);
}

test "insertPragma does not duplicate existing pragma" {
    const source =
        \\/** @format */
        \\const x = 1
    ;
    const out = try linter.format(source, .{ .semi = true, .insertPragma = true }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.count(u8, out, "@format") == 1);
}

test "requirePragma has priority over insertPragma" {
    const source =
        \\const x = 1
    ;
    const out = try linter.format(source, .{ .semi = true, .requirePragma = true, .insertPragma = true }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(source, out);
}

test "requirePragma line comment format" {
    const source =
        \\// @format
        \\const x = 1
    ;
    const out = try linter.format(source, .{ .semi = true, .requirePragma = true }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(
        \\// @format
        \\const x = 1;
    , out);
}

test "checkIgnorePragma defaults to false" {
    const opts: @import("common").FormatterOptions = .{};
    try std.testing.expectEqual(false, opts.checkIgnorePragma);
}

test "requirePragma defaults to false" {
    const opts: @import("common").FormatterOptions = .{};
    try std.testing.expectEqual(false, opts.requirePragma);
}

test "insertPragma defaults to false" {
    const opts: @import("common").FormatterOptions = .{};
    try std.testing.expectEqual(false, opts.insertPragma);
}

test "pragma config parsing" {

    var cfg = try linter.parseConfig(
        \\{
        \\  "formatter": {
        \\    "requirePragma": true,
        \\    "insertPragma": true,
        \\    "checkIgnorePragma": true
        \\  }
        \\}
    , std.testing.allocator);
    defer cfg.deinit(std.testing.allocator);
    try std.testing.expectEqual(true, cfg.formatter.options.requirePragma);
    try std.testing.expectEqual(true, cfg.formatter.options.insertPragma);
    try std.testing.expectEqual(true, cfg.formatter.options.checkIgnorePragma);
}
