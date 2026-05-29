const std = @import("std");
const compiler = @import("compiler");

const napi_env = ?*anyopaque;
const napi_value = ?*anyopaque;
const napi_callback_info = ?*anyopaque;
const napi_callback = *const fn (napi_env, napi_callback_info) callconv(.c) napi_value;

extern fn napi_create_function(env: napi_env, utf8name: [*c]const u8, length: usize, cb: napi_callback, data: ?*anyopaque, result: *napi_value) c_int;
extern fn napi_create_string_utf8(env: napi_env, str: [*c]const u8, length: usize, result: *napi_value) c_int;
extern fn napi_set_named_property(env: napi_env, object: napi_value, utf8name: [*c]const u8, value: napi_value) c_int;
extern fn napi_get_cb_info(env: napi_env, info: napi_callback_info, argc: *usize, argv: [*c]napi_value, this_arg: *napi_value, result: ?*?*anyopaque) c_int;
extern fn napi_get_value_string_utf8(env: napi_env, value: napi_value, buf: ?[*]u8, buf_size: usize, result: ?*usize) c_int;

const NAPI_OK: c_int = 0;

fn transformSource(env: napi_env, info: napi_callback_info) callconv(.c) napi_value {
    var argc: usize = 1;
    var argv: [1]napi_value = .{null};
    var this_arg: napi_value = null;
    if (napi_get_cb_info(env, info, &argc, @ptrCast(&argv), &this_arg, null) != NAPI_OK) return null;
    if (argc < 1) return null;

    var source_len: usize = 0;
    if (napi_get_value_string_utf8(env, argv[0], null, 0, &source_len) != NAPI_OK) return null;
    if (source_len == 0) return null;

    var buf = std.heap.page_allocator.alloc(u8, source_len + 1) catch return null;
    defer std.heap.page_allocator.free(buf);
    var written: usize = 0;
    if (napi_get_value_string_utf8(env, argv[0], buf.ptr, buf.len, &written) != NAPI_OK) return null;
    const source = buf[0..written];

    var threaded = std.Io.Threaded.init(std.heap.page_allocator, .{
        .async_limit = .nothing,
        .concurrent_limit = .nothing,
    });
    const io = threaded.io();

    const cfg = compiler.Config{};
    const compile_result = compiler.transform(source, "input.ts", cfg, io, std.heap.page_allocator) catch return null;
    defer compile_result.deinit(std.heap.page_allocator);

    const msg = std.fmt.allocPrint(std.heap.page_allocator, "transformed (code_len={d}, diagnostics={d})", .{ compile_result.code.len, compile_result.diagnostics.len }) catch return null;
    defer std.heap.page_allocator.free(msg);

    var result: napi_value = null;
    _ = napi_create_string_utf8(env, msg.ptr, msg.len, &result);
    return result;
}

pub export fn napi_register_module_v1(env: napi_env, exports: napi_value) napi_value {
    var fn_val: napi_value = null;
    _ = napi_create_function(env, "transform", 11, transformSource, null, &fn_val);
    _ = napi_set_named_property(env, exports, "transform", fn_val);
    return exports;
}
