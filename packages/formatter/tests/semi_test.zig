const std = @import("std");
const h = @import("harness");
const linter = @import("linter");

test "formatter package can remove semicolons" {
    const out = try linter.format("const x = 1;", .{ .semi = false }, std.testing.allocator);
    defer std.testing.allocator.free(out);

    try std.testing.expectEqualStrings("const x = 1", out);
}
