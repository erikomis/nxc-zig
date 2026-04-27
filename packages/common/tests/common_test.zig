const std = @import("std");

const common = @import("common");

test "common package computes source location" {
    const pos = common.sourcePosition("a\nb", 2);
    try std.testing.expectEqual(@as(u32, 2), pos.line);
    try std.testing.expectEqual(@as(u32, 1), pos.column);
}

test "common package normalizes path separators" {
    const out = try common.normalizePathSeparators("a\\b", std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("a/b", out);
}
