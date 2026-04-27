const std = @import("std");
const common = @import("common");
const linter = @import("linter");

pub const FormatterOptions = common.FormatterOptions;

pub fn fmt(source: []const u8, opts: FormatterOptions) ![]u8 {
    return linter.format(source, opts, std.testing.allocator);
}

pub fn testFormat(source: []const u8, opts: FormatterOptions, expected: []const u8) !void {
    const out = try linter.format(source, opts, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(expected, out);
}

pub fn testIdempotent(source: []const u8, opts: FormatterOptions) !void {
    const alloc = std.testing.allocator;
    const out1 = try linter.format(source, opts, alloc);
    defer alloc.free(out1);
    const out2 = try linter.format(out1, opts, alloc);
    defer alloc.free(out2);
    try std.testing.expectEqualStrings(out1, out2);
}
