const std = @import("std");
const compiler = @import("compiler");

const napi_env = ?*anyopaque;
const napi_value = ?*anyopaque;
const napi_callback_info = ?*anyopaque;
const napi_callback = *const fn (napi_env, napi_callback_info) callconv(.c) napi_value;

extern fn napi_create_function(env: napi_env, utf8name: [*c]const u8, length: usize, cb: napi_callback, data: ?*anyopaque, result: *napi_value) c_int;
extern fn napi_create_string_utf8(env: napi_env, str: [*c]const u8, length: usize, result: *napi_value) c_int;
extern fn napi_create_object(env: napi_env, result: *napi_value) c_int;
extern fn napi_create_array_with_length(env: napi_env, length: usize, result: *napi_value) c_int;
extern fn napi_create_int32(env: napi_env, value: i32, result: *napi_value) c_int;
extern fn napi_get_boolean(env: napi_env, value: bool, result: *napi_value) c_int;
extern fn napi_set_named_property(env: napi_env, object: napi_value, utf8name: [*c]const u8, value: napi_value) c_int;
extern fn napi_set_element(env: napi_env, object: napi_value, index: u32, value: napi_value) c_int;
extern fn napi_get_cb_info(env: napi_env, info: napi_callback_info, argc: *usize, argv: [*c]napi_value, this_arg: *napi_value, result: ?*?*anyopaque) c_int;
extern fn napi_get_value_string_utf8(env: napi_env, value: napi_value, buf: ?[*]u8, buf_size: usize, result: ?*usize) c_int;

const NAPI_OK: c_int = 0;

fn readStringArg(env: napi_env, arg: napi_value, alloc: std.mem.Allocator) ?[]u8 {
    var len: usize = 0;
    if (napi_get_value_string_utf8(env, arg, null, 0, &len) != NAPI_OK) return null;
    if (len == 0) return null;
    var buf = alloc.alloc(u8, len + 1) catch return null;
    var written: usize = 0;
    if (napi_get_value_string_utf8(env, arg, buf.ptr, buf.len, &written) != NAPI_OK) {
        alloc.free(buf);
        return null;
    }
    return buf[0..written];
}

fn parseSource(env: napi_env, info: napi_callback_info) callconv(.c) napi_value {
    var argc: usize = 1;
    var argv: [1]napi_value = .{null};
    var this_arg: napi_value = null;
    if (napi_get_cb_info(env, info, &argc, @ptrCast(&argv), &this_arg, null) != NAPI_OK) return null;
    if (argc < 1) return null;

    var arena_backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_backing.deinit();
    const alloc = arena_backing.allocator();

    const source = readStringArg(env, argv[0], alloc) orelse return null;

    const cfg = compiler.Config{};
    var parse_result = compiler.parse(source, "input.ts", cfg, alloc) catch return null;
    defer parse_result.deinit(alloc);

    // Build result object: { program, diagnostics }
    var result_obj: napi_value = null;
    _ = napi_create_object(env, &result_obj);

    // program
    var prog_val: napi_value = null;
    _ = napi_get_boolean(env, parse_result.program_id != null, &prog_val);
    _ = napi_set_named_property(env, result_obj, "program", prog_val);

    // diagnostics
    var diags_arr: napi_value = null;
    _ = napi_create_array_with_length(env, parse_result.diagnostics.len, &diags_arr);

    for (parse_result.diagnostics, 0..) |diag, i| {
        var diag_obj: napi_value = null;
        _ = napi_create_object(env, &diag_obj);

        var msg_val: napi_value = null;
        _ = napi_create_string_utf8(env, diag.message.ptr, diag.message.len, &msg_val);
        _ = napi_set_named_property(env, diag_obj, "message", msg_val);

        var sev_val: napi_value = null;
        const sev_str = switch (diag.severity) {
            .err => "error",
            .warn => "warning",
            .hint => "hint",
        };
        _ = napi_create_string_utf8(env, sev_str.ptr, sev_str.len, &sev_val);
        _ = napi_set_named_property(env, diag_obj, "severity", sev_val);

        var fname_val: napi_value = null;
        _ = napi_create_string_utf8(env, diag.filename.ptr, diag.filename.len, &fname_val);
        _ = napi_set_named_property(env, diag_obj, "filename", fname_val);

        var line_val: napi_value = null;
        _ = napi_create_int32(env, @intCast(diag.line), &line_val);
        _ = napi_set_named_property(env, diag_obj, "line", line_val);

        var col_val: napi_value = null;
        _ = napi_create_int32(env, @intCast(diag.col), &col_val);
        _ = napi_set_named_property(env, diag_obj, "column", col_val);

        _ = napi_set_element(env, diags_arr, @intCast(i), diag_obj);
    }

    _ = napi_set_named_property(env, result_obj, "diagnostics", diags_arr);

    return result_obj;
}

pub export fn napi_register_module_v1(env: napi_env, exports: napi_value) napi_value {
    var fn_val: napi_value = null;
    _ = napi_create_function(env, "parse", 7, parseSource, null, &fn_val);
    _ = napi_set_named_property(env, exports, "parse", fn_val);
    return exports;
}
