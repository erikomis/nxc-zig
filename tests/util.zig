const std = @import("std");

const compiler = @import("compiler");
const diagnostics = @import("diagnostics");

pub fn freeDiagnostics(alloc: std.mem.Allocator, diags: []const diagnostics.Diagnostic) void {
    for (diags) |d| {
        alloc.free(d.message);
        alloc.free(d.filename);
        if (d.source_line) |line| alloc.free(line);
    }
    alloc.free(diags);
}

pub fn deinitCompileResult(alloc: std.mem.Allocator, result: compiler.CompileResult) void {
    alloc.free(result.code);
    if (result.map) |m| alloc.free(m);
    if (result.declarations) |d| alloc.free(d);
    freeDiagnostics(alloc, result.diagnostics);
}

pub fn trimText(text: []const u8) []const u8 {
    return std.mem.trim(u8, text, " \n\r\t");
}

pub fn normalizedOutput(out: []const u8, expected: []const u8) []const u8 {
    const trimmed = trimText(out);
    const exp_trimmed = trimText(expected);
    const strict = "\"use strict\";";
    if (std.mem.startsWith(u8, exp_trimmed, strict)) return trimmed;
    if (!std.mem.startsWith(u8, trimmed, strict)) return trimmed;
    var rest = trimmed[strict.len..];
    if (std.mem.startsWith(u8, rest, "\r\n")) rest = rest[2..] else if (std.mem.startsWith(u8, rest, "\n")) rest = rest[1..];
    return trimText(rest);
}

pub fn equalIgnoringWhitespace(a: []const u8, b: []const u8) bool {
    return equalIgnoringWhitespaceWithOptions(a, b, true);
}

pub fn equalIgnoringWhitespaceStrict(a: []const u8, b: []const u8) bool {
    return equalIgnoringWhitespaceWithOptions(a, b, false);
}

fn equalIgnoringWhitespaceWithOptions(a: []const u8, b: []const u8, allow_quote_equivalence: bool) bool {
    var i: usize = 0;
    var j: usize = 0;
    while (true) {
        while (i < a.len and std.ascii.isWhitespace(a[i])) i += 1;
        while (j < b.len and std.ascii.isWhitespace(b[j])) j += 1;
        if (i == a.len or j == b.len) return i == a.len and j == b.len;
        if (a[i] != b[j]) {
            if (!allow_quote_equivalence or !((a[i] == '\'' or a[i] == '"') and (b[j] == '\'' or b[j] == '"'))) return false;
        }
        i += 1;
        j += 1;
    }
}

pub fn expectContainsText(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, haystack, needle) != null) return;
    std.debug.print("expected to find '{s}' in text\n", .{needle});
    return error.TestExpectedEqual;
}

pub fn expectContains(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, haystack, needle) != null) return;
    std.debug.print("\nexpected to find:\n{s}\nin:\n{s}\n", .{ needle, haystack });
    return error.TestExpectedEqual;
}

pub fn expectNotContains(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, haystack, needle) == null) return;
    std.debug.print("\nexpected not to find:\n{s}\nin:\n{s}\n", .{ needle, haystack });
    return error.TestExpectedEqual;
}

pub fn mkdirP(path: [:0]const u8) void {
    _ = std.os.linux.mkdirat(std.posix.AT.FDCWD, path.ptr, 0o755);
}

pub fn deleteTree(path: []const u8) void {
    std.Io.Dir.cwd().deleteTree(std.testing.io, path) catch {};
}

pub fn deleteTreeWithIo(io: anytype, path: []const u8) void {
    std.Io.Dir.cwd().deleteTree(io, path) catch {};
}

pub fn writeFile(path: []const u8, content: []const u8) !void {
    const fd = try std.posix.openat(std.posix.AT.FDCWD, path, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644);
    defer _ = std.os.linux.close(fd);
    var written: usize = 0;
    while (written < content.len) {
        const n = std.os.linux.write(fd, content.ptr + written, content.len - written);
        if (n == 0) break;
        written += n;
    }
}

pub fn readFile(path: []const u8, a: std.mem.Allocator) ![]u8 {
    const fd = try std.posix.openat(std.posix.AT.FDCWD, path, .{ .ACCMODE = .RDONLY }, 0);
    defer _ = std.os.linux.close(fd);
    var buf = std.ArrayListUnmanaged(u8).empty;
    var tmp: [4096]u8 = undefined;
    while (true) {
        const n = try std.posix.read(fd, &tmp);
        if (n == 0) break;
        try buf.appendSlice(a, tmp[0..n]);
    }
    return buf.toOwnedSlice(a);
}
