const std = @import("std");
const compiler = @import("compiler");
const linter = @import("linter");

const sample_ts =
    \\(function greetAll(names) {
    \\  for (const name of names) {
    \\    console.log("Hello, " + name + "!");
    \\  }
    \\})
    \\const users = ["Alice", "Bob", "Charlie"];
    \\greetAll(users);
;

const sample_js =
    \\(function greetAll(names) {
    \\  for (const name of names) {
    \\    console.log("Hello, " + name + "!");
    \\  }
    \\})
    \\const users = ["Alice", "Bob", "Charlie"];
    \\greetAll(users);
;

test "memory no growth on repeated compilation" {
    const alloc = std.testing.allocator;
    var cfg = compiler.Config{};
    cfg.parser.syntax = .typescript;
    cfg.jsx = false;
    cfg.check = false;

    const repetitions = 20;

    for (0..repetitions) |_| {
        var arena = std.heap.ArenaAllocator.init(alloc);
        defer arena.deinit();
        const a = arena.allocator();

        const result = try compiler.compile(sample_ts, "mem_test.ts", cfg, std.testing.io, a);
        defer result.deinit(a);

        try std.testing.expect(result.code.len > 0);
    }
}

test "memory repeated formatting" {
    const alloc = std.testing.allocator;

    const source =
        \\(function    foo(  )  {
        \\return   42
        \\})
    ;

    for (0..10) |_| {
        const formatted = try linter.format(source, .{}, alloc);
        defer alloc.free(formatted);
        try std.testing.expect(formatted.len > 0);
    }
}

test "memory compile with different configs" {
    const alloc = std.testing.allocator;

    const cfg1 = blk: {
        var c = compiler.Config{};
        c.parser.syntax = .typescript;
        c.jsx = false;
        c.check = false;
        break :blk c;
    };
    const cfg2 = blk: {
        var c = compiler.Config{};
        c.parser.syntax = .ecmascript;
        c.jsx = false;
        c.check = false;
        break :blk c;
    };

    const sources = [_][]const u8{ sample_ts, sample_js };

    for (sources, 0..) |src, i| {
        const cfg = if (i == 0) cfg1 else cfg2;
        var arena = std.heap.ArenaAllocator.init(alloc);
        defer arena.deinit();
        const a = arena.allocator();

        const result = try compiler.compile(src, "mem_cfg_test.js", cfg, std.testing.io, a);
        defer result.deinit(a);

        try std.testing.expect(result.code.len > 0);
    }
}

test "memory compile and free cycle" {
    const alloc = std.testing.allocator;
    var cfg = compiler.Config{};
    cfg.parser.syntax = .ecmascript;
    cfg.jsx = false;
    cfg.check = false;
    const source = "const x = 42; console.log(x);";

    for (0..15) |_| {
        const result = try compiler.compile(source, "mem_cycle.js", cfg, std.testing.io, alloc);
        defer result.deinit(alloc);
        try std.testing.expect(result.code.len > 0);
    }
}
