const std = @import("std");
const h = @import("harness");
const common = @import("common");
const linter = @import("linter");

test "formatter package uses general plugins" {
    const plugins = [_]common.Plugin{.{ .name = "svelte", .format = pluginFormat }};
    const out = try linter.format("ignored", .{ .plugins = &plugins }, std.testing.allocator);
    defer std.testing.allocator.free(out);

    try std.testing.expectEqualStrings("formatted by plugin\n", out);
}

fn pluginFormat(source: []const u8, options: common.FormatterOptions, alloc: std.mem.Allocator) !?[]u8 {
    _ = source;
    _ = options;
    return try alloc.dupe(u8, "formatted by plugin");
}
