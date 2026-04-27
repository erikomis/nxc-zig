const std = @import("std");
const compiler = @import("compiler");

fn generateLargeSource(size_bytes: usize, alloc: std.mem.Allocator) ![]u8 {
    var buf = try alloc.alloc(u8, size_bytes);
    errdefer alloc.free(buf);

    var written: usize = 0;
    var counter: u32 = 0;

    while (written < size_bytes) {
        const line = try std.fmt.allocPrint(alloc,
            \\const x{d} = {d};
            \\console.log(x{d});
            \\
        , .{ counter, counter * 2, counter });
        defer alloc.free(line);

        const copy_len = @min(line.len, size_bytes - written);
        @memcpy(buf[written .. written + copy_len], line[0..copy_len]);
        written += copy_len;
        counter += 1;

        if (counter > 20000) break;
    }

    return buf;
}

fn now() u64 {
    var tp: std.os.linux.timespec = undefined;
    _ = std.os.linux.clock_gettime(std.os.linux.CLOCK.MONOTONIC, &tp);
    return @as(u64, @intCast(tp.sec)) * 1_000_000_000 + @as(u64, @intCast(tp.nsec));
}

test "stress 100KB file" {
    const alloc = std.testing.allocator;
    const source = try generateLargeSource(100 * 1024, alloc);
    defer alloc.free(source);

    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const a = arena.allocator();

    const start = now();
    const cfg = compiler.Config{ .parser = .{ .syntax = .ecmascript }, .jsx = false, .check = false };
    const result = try compiler.compile(source, "stress_100kb.js", cfg, std.testing.io, a);
    defer result.deinit(a);

    const end = now();
    const elapsed_ms = @as(f64, @floatFromInt(end - start)) / 1_000_000.0;

    std.debug.print("\n100KB file: compiled in {d:.2}ms, output {d} bytes, {d} diagnostics\n", .{
        elapsed_ms, result.code.len, result.diagnostics.len,
    });

    try std.testing.expect(result.code.len > 0);
}

test "stress 1MB file" {
    const alloc = std.testing.allocator;
    const source = try generateLargeSource(1024 * 1024, alloc);
    defer alloc.free(source);

    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const a = arena.allocator();

    const start = now();
    const cfg = compiler.Config{ .parser = .{ .syntax = .ecmascript }, .jsx = false, .check = false };
    const result = try compiler.compile(source, "stress_1mb.js", cfg, std.testing.io, a);
    defer result.deinit(a);

    const end = now();
    const elapsed_ms = @as(f64, @floatFromInt(end - start)) / 1_000_000.0;

    std.debug.print("\n1MB file: compiled in {d:.2}ms, output {d} bytes, {d} diagnostics\n", .{
        elapsed_ms, result.code.len, result.diagnostics.len,
    });

    try std.testing.expect(result.code.len > 0);
}

test "stress repeated small compiles" {
    const alloc = std.testing.allocator;

    const source =
        \\const x = 42;
        \\function test() { return x * 2; }
        \\console.log(test());
    ;

    for (0..10) |_| {
        var arena = std.heap.ArenaAllocator.init(alloc);
        defer arena.deinit();
        const a = arena.allocator();

        const cfg = compiler.Config{ .parser = .{ .syntax = .ecmascript }, .jsx = false, .check = false };
        const result = try compiler.compile(source, "stress_repeat.js", cfg, std.testing.io, a);
        defer result.deinit(a);

        try std.testing.expect(result.code.len > 0);
    }

    std.debug.print("\nCompleted 10 repeated compiles without leak\n", .{});
}
