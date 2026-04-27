const std = @import("std");

const compiler = @import("compiler");

test "compiler package exposes parse api" {
    var result = try compiler.parse("const x: number = 1;", "test.ts", .{ .parser = .{ .syntax = .typescript } }, std.testing.allocator);
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.program_id != null);
    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
}

test "compiler package exposes transform api" {
    const result = try compiler.transform("const x: number = 1;", "test.ts", .{ .parser = .{ .syntax = .typescript } }, std.testing.io, std.testing.allocator);
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(std.mem.indexOf(u8, result.code, "const x = 1;") != null);
}
