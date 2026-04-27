const std = @import("std");
const compiler = @import("compiler");

const napi_env = ?*anyopaque;
const napi_value = ?*anyopaque;
const napi_callback_info = ?*anyopaque;
const napi_callback = *const fn (napi_env, napi_callback_info) callconv(.c) napi_value;

extern fn napi_create_function(
    env: napi_env,
    utf8name: [*c]const u8,
    length: usize,
    cb: napi_callback,
    data: ?*anyopaque,
    result: *napi_value,
) c_int;

extern fn napi_create_string_utf8(
    env: napi_env,
    str: [*c]const u8,
    length: usize,
    result: *napi_value,
) c_int;

extern fn napi_set_named_property(
    env: napi_env,
    object: napi_value,
    utf8name: [*c]const u8,
    value: napi_value,
) c_int;

const NAPI_OK: c_int = 0;

fn transformSource(env: napi_env, info: napi_callback_info) callconv(.c) napi_value {
    _ = info;
    var result: napi_value = null;
    const alloc = std.heap.page_allocator;

    var threaded = std.Io.Threaded.init(alloc, .{
        .async_limit = .nothing,
        .concurrent_limit = .nothing,
    });
    const io = threaded.io();

    const source = "const x: number = 1;";
    const cfg = compiler.Config{};
    const compile_result = compiler.transform(source, "test.ts", cfg, io, alloc) catch return null;
    defer compile_result.deinit(alloc);

    const msg = std.fmt.allocPrint(alloc, "transformed (code_len={d}, diagnostics={d})", .{ compile_result.code.len, compile_result.diagnostics.len }) catch return null;
    defer alloc.free(msg);

    if (napi_create_string_utf8(env, msg.ptr, msg.len, &result) != NAPI_OK) return null;
    return result;
}

pub export fn napi_register_module_v1(env: napi_env, exports: napi_value) napi_value {
    var fn_val: napi_value = null;
    if (napi_create_function(env, "transform", 9, transformSource, null, &fn_val) != NAPI_OK) return exports;
    _ = napi_set_named_property(env, exports, "transform", fn_val);
    return exports;
}
