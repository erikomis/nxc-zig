const std = @import("std");

const sourcemap = @import("sourcemap");

const SourceMap = sourcemap.SourceMap;

test "SourceMap emits valid sourcemap json with escaped sources and sourceRoot" {
    var sm = SourceMap.init(std.testing.allocator);
    defer sm.deinit();

    sm.source_root = "src\\root";
    const source_idx = try sm.addSource("foo\\bar\".zig", null);
    try std.testing.expectEqual(@as(u32, 0), source_idx);

    try sm.addMapping(.{
        .gen_line = 0,
        .gen_col = 0,
        .source_idx = source_idx,
        .src_line = 0,
        .src_col = 0,
    });

    const json = try sm.toJsonAlloc();
    defer std.testing.allocator.free(json);

    try std.testing.expectEqualStrings(
        "{\"version\":3,\"sourceRoot\":\"src\\\\root\",\"sources\":[\"foo\\\\bar\\\".zig\"],\"names\":[],\"mappings\":\"AAAA\"}",
        json,
    );
}

test "SourceMap sorts mappings before VLQ encoding" {
    var sm = SourceMap.init(std.testing.allocator);
    defer sm.deinit();

    const source_idx = try sm.addSource("foo.zig", null);

    try sm.addMapping(.{
        .gen_line = 1,
        .gen_col = 0,
        .source_idx = source_idx,
        .src_line = 1,
        .src_col = 0,
    });
    try sm.addMapping(.{
        .gen_line = 0,
        .gen_col = 3,
        .source_idx = source_idx,
        .src_line = 0,
        .src_col = 4,
    });

    const json = try sm.toJsonAlloc();
    defer std.testing.allocator.free(json);

    try std.testing.expectEqualStrings(
        "{\"version\":3,\"sources\":[\"foo.zig\"],\"names\":[],\"mappings\":\"GAAI;AACJ\"}",
        json,
    );
}

test "SourceMap encodes multi-line mappings correctly" {
    var sm = SourceMap.init(std.testing.allocator);
    defer sm.deinit();

    const si = try sm.addSource("test.ts", null);

    try sm.addMapping(.{ .gen_line = 0, .gen_col = 0, .source_idx = si, .src_line = 0, .src_col = 0 });
    try sm.addMapping(.{ .gen_line = 1, .gen_col = 0, .source_idx = si, .src_line = 1, .src_col = 0 });
    try sm.addMapping(.{ .gen_line = 2, .gen_col = 4, .source_idx = si, .src_line = 2, .src_col = 8 });

    const json = try sm.toJsonAlloc();
    defer std.testing.allocator.free(json);

    try std.testing.expect(json.len > 20);
    try std.testing.expect(std.mem.indexOf(u8, json, "AAAA") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "test.ts") != null);
}

test "SourceMap handles no mappings gracefully" {
    var sm = SourceMap.init(std.testing.allocator);
    defer sm.deinit();

    _ = try sm.addSource("empty.ts", null);
    const json = try sm.toJsonAlloc();
    defer std.testing.allocator.free(json);

    try std.testing.expectEqualStrings(
        "{\"version\":3,\"sources\":[\"empty.ts\"],\"names\":[],\"mappings\":\"\"}",
        json,
    );
}

test "SourceMap with multiple sources" {
    var sm = SourceMap.init(std.testing.allocator);
    defer sm.deinit();

    const s0 = try sm.addSource("a.ts", null);
    const s1 = try sm.addSource("b.ts", null);

    try sm.addMapping(.{ .gen_line = 0, .gen_col = 0, .source_idx = s0, .src_line = 0, .src_col = 0 });
    try sm.addMapping(.{ .gen_line = 0, .gen_col = 5, .source_idx = s1, .src_line = 3, .src_col = 1 });
    try sm.addMapping(.{ .gen_line = 1, .gen_col = 0, .source_idx = s0, .src_line = 1, .src_col = 0 });

    const json = try sm.toJsonAlloc();
    defer std.testing.allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "a.ts") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "b.ts") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"sources\":[\"a.ts\",\"b.ts\"]") != null);
}
