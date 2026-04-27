const std = @import("std");
const compiler = @import("compiler");
const linter = @import("linter");

const sample_code =
    \\function fibonacci(n: number): number {
    \\  if (n <= 1) return n;
    \\  return fibonacci(n - 1) + fibonacci(n - 2);
    \\}
    \\
    \\interface Person {
    \\  name: string;
    \\  age: number;
    \\  email?: string;
    \\}
    \\
    \\class Greeter {
    \\  private greeting: string;
    \\
    \\  constructor(message: string) {
    \\    this.greeting = message;
    \\  }
    \\
    \\  greet(name: string): string {
    \\    return `${this.greeting}, ${name}!`;
    \\  }
    \\}
    \\
    \\const people: Person[] = [
    \\  { name: "Alice", age: 30 },
    \\  { name: "Bob", age: 25, email: "bob@test.com" },
    \\];
    \\
    \\const greeter = new Greeter("Hello");
    \\people.forEach(p => console.log(greeter.greet(p.name)));
    \\
;

const Iterations = 1;

const Baseline = struct {
    timestamp: i64,
    git_hash: []const u8,
    compiler_ns: u64,
    formatter_ns: u64,
    linter_ns: u64,
    iterations: usize,
};

fn saveBaseline(comp_timing: Timing, fmt_timing: Timing, lint_timing: Timing, alloc: std.mem.Allocator) !void {
    var now_tp: std.os.linux.timespec = undefined;
    _ = std.os.linux.clock_gettime(std.os.linux.CLOCK.REALTIME, &now_tp);
    const ts = @as(i64, @intCast(now_tp.sec));
    const json_str = try std.fmt.allocPrint(alloc,
        \\{{
        \\  "timestamp": {d},
        \\  "git_hash": "unknown",
        \\  "compiler_ns": {d},
        \\  "formatter_ns": {d},
        \\  "linter_ns": {d},
        \\  "iterations": {d}
        \\}}
    , .{
        ts,
        comp_timing.avg,
        fmt_timing.avg,
        lint_timing.avg,
        Iterations,
    });
    defer alloc.free(json_str);

    const file = std.Io.Dir.cwd().createFile(std.testing.io, "bench_baseline.json", .{ .truncate = true }) catch |err| {
        std.debug.print("warning: could not save benchmark baseline: {}\n", .{err});
        return;
    };
    defer file.close(std.testing.io);
    try file.writeStreamingAll(std.testing.io, json_str);
}

fn loadBaseline(alloc: std.mem.Allocator) !?Baseline {
    const content = std.Io.Dir.cwd().readFileAlloc(std.testing.io, "bench_baseline.json", alloc, std.Io.Limit.limited(1024 * 1024)) catch return null;
    defer alloc.free(content);

    const ts = extractJsonField(u64, content, "timestamp") orelse return null;
    const comp = extractJsonField(u64, content, "compiler_ns") orelse return null;
    const fmt = extractJsonField(u64, content, "formatter_ns") orelse return null;
    const lint = extractJsonField(u64, content, "linter_ns") orelse return null;
    const iters = extractJsonField(usize, content, "iterations") orelse return null;

    return Baseline{
        .timestamp = @intCast(ts),
        .git_hash = try std.heap.page_allocator.dupe(u8, "unknown"),
        .compiler_ns = comp,
        .formatter_ns = fmt,
        .linter_ns = lint,
        .iterations = iters,
    };
}

fn extractJsonField(comptime T: type, json_str: []const u8, key: []const u8) ?T {
    const search = std.fmt.allocPrint(std.heap.page_allocator, "\"{s}\":", .{key}) catch return null;
    defer std.heap.page_allocator.free(search);
    const idx = std.mem.indexOf(u8, json_str, search) orelse return null;
    const start = idx + search.len;
    var end = start;
    while (end < json_str.len and json_str[end] != ',' and json_str[end] != '\n' and json_str[end] != '}') end += 1;
    const val_str = std.mem.trim(u8, json_str[start..end], " \t\r\n");
    if (T == u64) {
        return @intCast(std.fmt.parseInt(u64, val_str, 10) catch return null);
    }
    if (T == usize) {
        return std.fmt.parseInt(usize, val_str, 10) catch return null;
    }
    return null;
}

fn checkRegressions(current: u64, baseline: u64, label: []const u8) void {
    if (current > baseline * 12 / 10) {
        std.debug.print("WARNING: {s} regression of {d:0.1}% vs baseline\n", .{
            label,
            @as(f64, @floatFromInt(current - baseline)) / @as(f64, @floatFromInt(baseline)) * 100.0,
        });
    }
}

const Timing = struct {
    min: u64,
    max: u64,
    avg: u64,
    total: u64,
};

fn now() u64 {
    var tp: std.os.linux.timespec = undefined;
    _ = std.os.linux.clock_gettime(std.os.linux.CLOCK.MONOTONIC, &tp);
    return @as(u64, @intCast(tp.sec)) * 1_000_000_000 + @as(u64, @intCast(tp.nsec));
}

fn runTimed(comptime func: anytype, args: anytype, iterations: usize, alloc: std.mem.Allocator) !Timing {
    var min: u64 = std.math.maxInt(u64);
    var max: u64 = 0;
    var total: u64 = 0;

    for (0..iterations) |_| {
        var arena = std.heap.ArenaAllocator.init(alloc);
        defer arena.deinit();
        const a = arena.allocator();

        const start = now();
        _ = try @call(.auto, func, args ++ .{a});
        const end = now();
        const elapsed = end - start;

        total += elapsed;
        if (elapsed < min) min = elapsed;
        if (elapsed > max) max = elapsed;
    }

    return .{
        .min = min,
        .max = max,
        .avg = total / iterations,
        .total = total,
    };
}

fn formatTiming(label: []const u8, t: Timing) void {
    const min_ms = @as(f64, @floatFromInt(t.min)) / 1_000_000.0;
    const max_ms = @as(f64, @floatFromInt(t.max)) / 1_000_000.0;
    const avg_ms = @as(f64, @floatFromInt(t.avg)) / 1_000_000.0;
    std.debug.print("{s}: min={d:.2}ms avg={d:.2}ms max={d:.2}ms (over {d} runs)\n", .{ label, min_ms, avg_ms, max_ms, Iterations });
}

fn benchCompiler(code: []const u8, alloc: std.mem.Allocator) !compiler.CompileResult {
    const cfg = compiler.Config{ .parser = .{ .syntax = .typescript }, .jsx = false, .source_maps = false, .declaration = false };
    return compiler.compile(code, "bench.ts", cfg, std.testing.io, alloc);
}

fn benchFormatter(code: []const u8, alloc: std.mem.Allocator) ![]u8 {
    return linter.format(code, .{}, alloc);
}

fn benchLinter(code: []const u8, alloc: std.mem.Allocator) !linter.Result {
    return linter.lintWithConfig(code, "bench.ts", .{}, alloc);
}

test "bench compiler" {
    const alloc = std.testing.allocator;
    const code = try alloc.dupe(u8, sample_code);
    defer alloc.free(code);

    const comp_timing = try runTimed(benchCompiler, .{code}, Iterations, alloc);
    formatTiming("compiler", comp_timing);

    if (try loadBaseline(alloc)) |baseline| {
        checkRegressions(comp_timing.avg, baseline.compiler_ns, "compiler");
    }

    try std.testing.expect(comp_timing.avg > 0);
}

test "bench formatter" {
    const alloc = std.testing.allocator;
    const code = try alloc.dupe(u8, sample_code);
    defer alloc.free(code);

    const fmt_timing = try runTimed(benchFormatter, .{code}, Iterations, alloc);
    formatTiming("formatter", fmt_timing);

    if (try loadBaseline(alloc)) |baseline| {
        checkRegressions(fmt_timing.avg, baseline.formatter_ns, "formatter");
    }

    try std.testing.expect(fmt_timing.avg > 0);
}

test "bench linter" {
    const alloc = std.testing.allocator;
    const code = try alloc.dupe(u8, sample_code);
    defer alloc.free(code);

    const lint_timing = try runTimed(benchLinter, .{code}, Iterations, alloc);
    formatTiming("linter", lint_timing);

    if (try loadBaseline(alloc)) |baseline| {
        checkRegressions(lint_timing.avg, baseline.linter_ns, "linter");
    }

    try std.testing.expect(lint_timing.avg > 0);
}

test "bench all and save baseline" {
    const alloc = std.testing.allocator;
    const code = try alloc.dupe(u8, sample_code);
    defer alloc.free(code);

    const comp_timing = try runTimed(benchCompiler, .{code}, Iterations, alloc);
    formatTiming("compiler", comp_timing);

    const fmt_timing = try runTimed(benchFormatter, .{code}, Iterations, alloc);
    formatTiming("formatter", fmt_timing);

    const lint_timing = try runTimed(benchLinter, .{code}, Iterations, alloc);
    formatTiming("linter", lint_timing);

    try saveBaseline(comp_timing, fmt_timing, lint_timing, alloc);
}
