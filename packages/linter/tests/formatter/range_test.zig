const std = @import("std");
const h = @import("harness");
const linter = @import("linter");

test "rangeStart formats only from offset" {
    const source =
        \\const a = 1
        \\const b = 2
        \\const c = 3
    ;
    const out = try linter.format(source, .{
        .semi = true, .rangeStart = 11, .rangeEnd = std.math.maxInt(usize)
    }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(
        \\const a = 1
        \\const b = 2;
        \\const c = 3;
    , out);
}

test "rangeEnd formats only up to offset" {
    const source =
        \\const a = 1
        \\const b = 2
        \\const c = 3
    ;
    const out = try linter.format(source, .{
        .semi = true, .rangeStart = 0, .rangeEnd = 22
    }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(
        \\const a = 1;
        \\const b = 2;
        \\const c = 3
    , out);
}

test "rangeStart and rangeEnd together" {
    const source =
        \\const a = 1
        \\const b = 2
        \\const c = 3
        \\const d = 4
    ;
    const out = try linter.format(source, .{
        .semi = true, .rangeStart = 11, .rangeEnd = 33
    }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(
        \\const a = 1
        \\const b = 2;
        \\const c = 3;
        \\const d = 4
    , out);
}

test "range extends to line boundaries" {
    const source =
        \\const a = 1
        \\const b = 2
        \\const c = 3
    ;
    const out = try linter.format(source, .{
        .semi = true, .rangeStart = 12, .rangeEnd = 22
    }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(
        \\const a = 1
        \\const b = 2;
        \\const c = 3
    , out);
}

test "rangeStart defaults to 0" {
    const opts: @import("common").FormatterOptions = .{};
    try std.testing.expectEqual(@as(usize, 0), opts.rangeStart);
}

test "rangeEnd defaults to maxInt" {
    const opts: @import("common").FormatterOptions = .{};
    try std.testing.expectEqual(std.math.maxInt(usize), opts.rangeEnd);
}

test "rangeStart and rangeEnd config parsing" {

    var cfg = try linter.parseConfig(
        \\{
        \\  "formatter": {
        \\    "rangeStart": 5,
        \\    "rangeEnd": 100
        \\  }
        \\}
    , std.testing.allocator);
    defer cfg.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 5), cfg.formatter.options.rangeStart);
    try std.testing.expectEqual(@as(usize, 100), cfg.formatter.options.rangeEnd);
}
