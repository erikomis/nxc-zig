const std = @import("std");
const compiler = @import("compiler");

const samples = [_][]const u8{
    \\const x = 1; console.log(x);
    ,
    \\function add(a, b) { return a + b; } console.log(add(2, 3));
    ,
    \\const arr = [1,2,3]; console.log(arr.map(x => x * 2));
    ,
    \\class A { constructor(v) { this.v = v; } get() { return this.v; } }
    \\const a = new A(42); console.log(a.get());
    ,
    \\const obj = { a: 1, b: 2 }; console.log(obj.a + obj.b);
    ,
};

test "concurrent compilations" {
    const alloc = std.testing.allocator;
    const cfg = compiler.Config{ .parser = .{ .syntax = .ecmascript }, .jsx = false, .check = false };

    for (samples, 0..) |source, i| {
        var arena = std.heap.ArenaAllocator.init(alloc);
        defer arena.deinit();
        const a = arena.allocator();

        const result = compiler.compile(source, "concurrent.js", cfg, std.testing.io, a) catch |err| {
            std.debug.print("sample {d} failed: {s}\n", .{ i, @errorName(err) });
            continue;
        };
        defer result.deinit(a);

        try std.testing.expect(result.code.len > 0);
    }
}

test "parallel compile same source" {
    const alloc = std.testing.allocator;
    const source =
        \\const x = 42; console.log(x);
    ;
    const cfg = compiler.Config{ .parser = .{ .syntax = .ecmascript }, .jsx = false, .check = false };
    const parallelism = 8;

    var outputs = std.ArrayListUnmanaged([]const u8).empty;
    defer {
        for (outputs.items) |o| alloc.free(o);
        outputs.deinit(alloc);
    }

    for (0..parallelism) |_| {
        var arena = std.heap.ArenaAllocator.init(alloc);
        defer arena.deinit();
        const a = arena.allocator();

        const result = try compiler.compile(source, "parallel.js", cfg, std.testing.io, a);
        defer result.deinit(a);

        const duped = try alloc.dupe(u8, result.code);
        try outputs.append(alloc, duped);
    }

    for (1..outputs.items.len) |i| {
        try std.testing.expect(std.mem.eql(u8, outputs.items[0], outputs.items[i]));
    }
}

test "deterministic output" {
    const alloc = std.testing.allocator;
    const source =
        \\const items = [3, 1, 4, 1, 5, 9];
        \\console.log(items.sort());
    ;
    const cfg = compiler.Config{ .parser = .{ .syntax = .ecmascript }, .jsx = false, .check = false };

    var prev: ?[]const u8 = null;

    for (0..5) |_| {
        var arena = std.heap.ArenaAllocator.init(alloc);
        defer arena.deinit();
        const a = arena.allocator();

        const result = try compiler.compile(source, "deterministic.js", cfg, std.testing.io, a);
        defer result.deinit(a);

        if (prev) |p| {
            try std.testing.expect(std.mem.eql(u8, p, result.code));
            alloc.free(p);
        }
        prev = try alloc.dupe(u8, result.code);
    }

    if (prev) |p| alloc.free(p);
}
