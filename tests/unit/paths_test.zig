const std = @import("std");

const paths = @import("paths");
const util = @import("../util.zig");

const resolveFullPath = paths.resolveFullPath;
const mkdirP = util.mkdirP;
const deleteTree = util.deleteTree;
const writeFile = util.writeFile;

test "resolveFullPath resolves dot import to index.js" {
    const alloc = std.testing.allocator;

    const root = "/tmp/zts_paths_dot_import";
    mkdirP(root);
    mkdirP(root ++ "/src");
    defer deleteTree(root);

    try writeFile(root ++ "/src/index.ts", "export default 1;");

    const resolved = try resolveFullPath(".", std.testing.io, .{
        .add_js_extension = true,
        .src_dir = root ++ "/src",
    }, alloc);
    defer if (resolved.ptr != ".".ptr) alloc.free(resolved);

    try std.testing.expectEqualStrings("./index.js", resolved);
}

test "resolveFullPath preserves suffix when resolving dot import to index.js" {
    const alloc = std.testing.allocator;

    const root = "/tmp/zts_paths_dot_import_suffix";
    mkdirP(root);
    mkdirP(root ++ "/src");
    defer deleteTree(root);

    try writeFile(root ++ "/src/index.tsx", "export default 1;");

    const resolved = try resolveFullPath(".?raw", std.testing.io, .{
        .add_js_extension = true,
        .src_dir = root ++ "/src",
    }, alloc);
    defer if (resolved.ptr != ".?raw".ptr) alloc.free(resolved);

    try std.testing.expectEqualStrings("./index.js?raw", resolved);
}

test "resolveFullPath resolves parent directory import to parent index.js" {
    const alloc = std.testing.allocator;

    const root = "/tmp/zts_paths_parent_import";
    mkdirP(root);
    mkdirP(root ++ "/src");
    mkdirP(root ++ "/src/feature");
    defer deleteTree(root);

    try writeFile(root ++ "/src/index.ts", "export default 1;");

    const resolved = try resolveFullPath("..", std.testing.io, .{
        .add_js_extension = true,
        .src_dir = root ++ "/src/feature",
    }, alloc);
    defer if (resolved.ptr != "..".ptr) alloc.free(resolved);

    try std.testing.expectEqualStrings("../index.js", resolved);
}
