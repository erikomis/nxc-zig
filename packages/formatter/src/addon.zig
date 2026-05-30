const std = @import("std");
const linter = @import("linter");
const common = @import("common");

const napi_env = ?*anyopaque;
const napi_value = ?*anyopaque;
const napi_callback_info = ?*anyopaque;
const napi_callback = *const fn (napi_env, napi_callback_info) callconv(.c) napi_value;

extern fn napi_create_function(env: napi_env, utf8name: [*c]const u8, length: usize, cb: napi_callback, data: ?*anyopaque, result: *napi_value) c_int;
extern fn napi_create_string_utf8(env: napi_env, str: [*c]const u8, length: usize, result: *napi_value) c_int;
extern fn napi_create_object(env: napi_env, result: *napi_value) c_int;
extern fn napi_create_array(env: napi_env, result: *napi_value) c_int;
extern fn napi_create_array_with_length(env: napi_env, length: usize, result: *napi_value) c_int;
extern fn napi_create_double(env: napi_env, value: f64, result: *napi_value) c_int;
extern fn napi_create_int64(env: napi_env, value: i64, result: *napi_value) c_int;
extern fn napi_create_uint64(env: napi_env, value: u64, result: *napi_value) c_int;
extern fn napi_get_boolean(env: napi_env, value: bool, result: *napi_value) c_int;
extern fn napi_set_named_property(env: napi_env, object: napi_value, utf8name: [*c]const u8, value: napi_value) c_int;
extern fn napi_set_element(env: napi_env, object: napi_value, index: u32, value: napi_value) c_int;
extern fn napi_get_cb_info(env: napi_env, info: napi_callback_info, argc: *usize, argv: [*c]napi_value, this_arg: *napi_value, result: ?*?*anyopaque) c_int;
extern fn napi_get_value_string_utf8(env: napi_env, value: napi_value, buf: ?[*]u8, buf_size: usize, result: ?*usize) c_int;
extern fn napi_get_value_bool(env: napi_env, value: napi_value, result: *bool) c_int;
extern fn napi_get_value_int64(env: napi_env, value: napi_value, result: *i64) c_int;
extern fn napi_get_array_length(env: napi_env, value: napi_value, result: *u32) c_int;
extern fn napi_get_named_property(env: napi_env, object: napi_value, utf8name: [*c]const u8, result: *napi_value) c_int;
extern fn napi_get_element(env: napi_env, object: napi_value, index: u32, result: *napi_value) c_int;
extern fn napi_typeof(env: napi_env, value: napi_value, result: *napi_valuetype) c_int;

const napi_valuetype = enum(c_int) {
    undefined = 0,
    null = 1,
    boolean = 2,
    number = 3,
    string = 4,
    symbol = 5,
    object = 6,
    function = 7,
    external = 8,
    bigint = 9,
};

const NAPI_OK: c_int = 0;

fn optsFromArgs(env: napi_env, info: napi_callback_info) common.FormatterOptions {
    var argc: usize = 1;
    var argv: [1]napi_value = .{null};
    var this_arg: napi_value = null;
    if (napi_get_cb_info(env, info, &argc, @ptrCast(&argv), &this_arg, null) != NAPI_OK) return .{};
    if (argc < 1) return .{};

    var val_type: napi_valuetype = .undefined;
    if (napi_typeof(env, argv[0], &val_type) != NAPI_OK) return .{};
    if (val_type != .object) return .{};

    var opts = common.FormatterOptions{};
    const obj = argv[0];

    var prop: napi_value = null;
    if (napi_get_named_property(env, obj, "singleQuote", &prop) == NAPI_OK) {
        var val_type2: napi_valuetype = .undefined;
        if (napi_typeof(env, prop, &val_type2) == NAPI_OK and val_type2 == .boolean) {
            _ = napi_get_value_bool(env, prop, &opts.singleQuote);
        }
    }
    if (napi_get_named_property(env, obj, "semi", &prop) == NAPI_OK) {
        var val_type2: napi_valuetype = .undefined;
        if (napi_typeof(env, prop, &val_type2) == NAPI_OK and val_type2 == .boolean) {
            _ = napi_get_value_bool(env, prop, &opts.semi);
        }
    }
    if (napi_get_named_property(env, obj, "trailingComma", &prop) == NAPI_OK) {
        var val_type2: napi_valuetype = .undefined;
        if (napi_typeof(env, prop, &val_type2) == NAPI_OK and val_type2 == .string) {
            var buf: [64]u8 = undefined;
            var len: usize = 0;
            if (napi_get_value_string_utf8(env, prop, &buf, buf.len, &len) == NAPI_OK and len > 0) {
                opts.trailingComma = std.meta.stringToEnum(common.TrailingComma, buf[0..len]) orelse .all;
            }
        }
    }
    if (napi_get_named_property(env, obj, "bracketSpacing", &prop) == NAPI_OK) {
        var val_type2: napi_valuetype = .undefined;
        if (napi_typeof(env, prop, &val_type2) == NAPI_OK and val_type2 == .boolean) {
            _ = napi_get_value_bool(env, prop, &opts.bracketSpacing);
        }
    }
    if (napi_get_named_property(env, obj, "useTabs", &prop) == NAPI_OK) {
        var val_type2: napi_valuetype = .undefined;
        if (napi_typeof(env, prop, &val_type2) == NAPI_OK and val_type2 == .boolean) {
            _ = napi_get_value_bool(env, prop, &opts.useTabs);
        }
    }
    if (napi_get_named_property(env, obj, "tabWidth", &prop) == NAPI_OK) {
        var val: i64 = 0;
        if (napi_get_value_int64(env, prop, &val) == NAPI_OK and val > 0) {
            opts.tabWidth = @intCast(val);
        }
    }
    if (napi_get_named_property(env, obj, "printWidth", &prop) == NAPI_OK) {
        var val: i64 = 0;
        if (napi_get_value_int64(env, prop, &val) == NAPI_OK and val > 0) {
            opts.printWidth = @intCast(val);
        }
    }
    if (napi_get_named_property(env, obj, "arrowParens", &prop) == NAPI_OK) {
        var val_type2: napi_valuetype = .undefined;
        if (napi_typeof(env, prop, &val_type2) == NAPI_OK and val_type2 == .string) {
            var buf: [64]u8 = undefined;
            var len: usize = 0;
            if (napi_get_value_string_utf8(env, prop, &buf, buf.len, &len) == NAPI_OK and len > 0) {
                opts.arrowParens = std.meta.stringToEnum(common.ArrowParens, buf[0..len]) orelse .always;
            }
        }
    }
    if (napi_get_named_property(env, obj, "endOfLine", &prop) == NAPI_OK) {
        var val_type2: napi_valuetype = .undefined;
        if (napi_typeof(env, prop, &val_type2) == NAPI_OK and val_type2 == .string) {
            var buf: [64]u8 = undefined;
            var len: usize = 0;
            if (napi_get_value_string_utf8(env, prop, &buf, buf.len, &len) == NAPI_OK and len > 0) {
                opts.endOfLine = std.meta.stringToEnum(common.EndOfLine, buf[0..len]) orelse .lf;
            }
        }
    }
    if (napi_get_named_property(env, obj, "bracketSameLine", &prop) == NAPI_OK) {
        var val_type2: napi_valuetype = .undefined;
        if (napi_typeof(env, prop, &val_type2) == NAPI_OK and val_type2 == .boolean) {
            _ = napi_get_value_bool(env, prop, &opts.bracketSameLine);
        }
    }

    return opts;
}

fn formatFn(env: napi_env, info: napi_callback_info) callconv(.c) napi_value {
    var argc: usize = 2;
    var argv: [2]napi_value = .{ null, null };
    var this_arg: napi_value = null;
    if (napi_get_cb_info(env, info, &argc, @ptrCast(&argv), &this_arg, null) != NAPI_OK) return null;
    if (argc < 1) return null;

    var source_len: usize = 0;
    _ = napi_get_value_string_utf8(env, argv[0], null, 0, &source_len);
    if (source_len == 0) return null;

    var buf = std.heap.page_allocator.alloc(u8, source_len + 1) catch return null;
    defer std.heap.page_allocator.free(buf);
    var written: usize = 0;
    if (napi_get_value_string_utf8(env, argv[0], buf.ptr, buf.len, &written) != NAPI_OK) return null;
    const source = buf[0..written];

    var opts = common.FormatterOptions{};
    if (argc >= 2) {
        var val_type: napi_valuetype = .undefined;
        if (napi_typeof(env, argv[1], &val_type) == NAPI_OK and val_type == .object) {
            opts = optsFromArgs(env, info);
        }
    }

    const formatted = linter.format(source, opts, std.heap.page_allocator) catch return null;
    defer std.heap.page_allocator.free(formatted);

    var result: napi_value = null;
    if (napi_create_string_utf8(env, formatted.ptr, formatted.len, &result) != NAPI_OK) return null;
    return result;
}

pub export fn napi_register_module_v1(env: napi_env, exports: napi_value) napi_value {
    var format_fn_val: napi_value = null;
    if (napi_create_function(env, "format", 6, formatFn, null, &format_fn_val) == NAPI_OK) {
        _ = napi_set_named_property(env, exports, "format", format_fn_val);
    }

    return exports;
}
