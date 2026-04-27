const std = @import("std");
const h = @import("harness");
const linter = @import("linter");

test "formatter respects arrowParens always for single param" {
    const out = try linter.format("const fn = x => x", .{ .singleQuote = true, .semi = false, .arrowParens = .always }, std.testing.allocator);
    defer std.testing.allocator.free(out);

    try std.testing.expectEqualStrings("const fn = (x) => x", out);
}

test "formatter respects arrowParens avoid for single param" {
    const out = try linter.format("const fn = (x) => x", .{ .singleQuote = true, .semi = false, .arrowParens = .avoid }, std.testing.allocator);
    defer std.testing.allocator.free(out);

    try std.testing.expectEqualStrings("const fn = x => x", out);
}

test "formatter respects arrowParens always for async single param" {
    const out = try linter.format("const fn = async x => x", .{ .singleQuote = true, .semi = false, .arrowParens = .always }, std.testing.allocator);
    defer std.testing.allocator.free(out);

    try std.testing.expectEqualStrings("const fn = async (x) => x", out);
}

test "formatter keeps required arrow param parens in avoid mode" {
    const out = try linter.format("const fn = ({x}) => x", .{ .singleQuote = true, .semi = false, .arrowParens = .avoid }, std.testing.allocator);
    defer std.testing.allocator.free(out);

    try std.testing.expectEqualStrings("const fn = ({ x }) => x", out);
}

test "formatter preserves typed arrow params" {
    const out = try linter.format("const sum = (v: number) => v * 4", .{ .singleQuote = true, .semi = false, .arrowParens = .always }, std.testing.allocator);
    defer std.testing.allocator.free(out);

    try std.testing.expectEqualStrings("const sum = (v: number) => v * 4", out);
}

test "formatter keeps typed arrow param parens in avoid mode" {
    const out = try linter.format("const sum = (v: number) => v * 4", .{ .singleQuote = true, .semi = false, .arrowParens = .avoid }, std.testing.allocator);
    defer std.testing.allocator.free(out);

    try std.testing.expectEqualStrings("const sum = (v: number) => v * 4", out);
}
