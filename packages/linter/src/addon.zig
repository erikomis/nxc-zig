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
extern fn napi_create_array_with_length(env: napi_env, length: usize, result: *napi_value) c_int;
extern fn napi_create_int64(env: napi_env, value: i64, result: *napi_value) c_int;
extern fn napi_get_boolean(env: napi_env, value: bool, result: *napi_value) c_int;
extern fn napi_set_named_property(env: napi_env, object: napi_value, utf8name: [*c]const u8, value: napi_value) c_int;
extern fn napi_set_element(env: napi_env, object: napi_value, index: u32, value: napi_value) c_int;
extern fn napi_get_cb_info(env: napi_env, info: napi_callback_info, argc: *usize, argv: [*c]napi_value, this_arg: *napi_value, result: ?*?*anyopaque) c_int;
extern fn napi_get_value_string_utf8(env: napi_env, value: napi_value, buf: ?[*]u8, buf_size: usize, result: ?*usize) c_int;
extern fn napi_get_value_bool(env: napi_env, value: napi_value, result: *bool) c_int;
extern fn napi_get_value_int64(env: napi_env, value: napi_value, result: *i64) c_int;
extern fn napi_typeof(env: napi_env, value: napi_value, result: *napi_valuetype) c_int;
extern fn napi_get_named_property(env: napi_env, object: napi_value, utf8name: [*c]const u8, result: *napi_value) c_int;

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

fn lintFn(env: napi_env, info: napi_callback_info) callconv(.c) napi_value {
    var argc: usize = 2;
    var argv: [2]napi_value = .{ null, null };
    var this_arg: napi_value = null;
    _ = napi_get_cb_info(env, info, &argc, @ptrCast(&argv), &this_arg, null);
    if (argc < 1) return null;

    var source_len: usize = 0;
    _ = napi_get_value_string_utf8(env, argv[0], null, 0, &source_len);
    if (source_len == 0) return null;

    var buf = std.heap.page_allocator.alloc(u8, source_len + 1) catch return null;
    defer std.heap.page_allocator.free(buf);
    var written: usize = 0;
    if (napi_get_value_string_utf8(env, argv[0], buf.ptr, buf.len, &written) != NAPI_OK) return null;
    const source = buf[0..written];

    var cfg = linter.Config{};
    if (argc >= 2) {
        var val_type: napi_valuetype = .undefined;
        if (napi_typeof(env, argv[1], &val_type) == NAPI_OK and val_type == .object) {
            const obj = argv[1];

            var fmt_prop: napi_value = null;
            if (napi_get_named_property(env, obj, "formatter", &fmt_prop) == NAPI_OK) {
                var fmt_type: napi_valuetype = .undefined;
                if (napi_typeof(env, fmt_prop, &fmt_type) == NAPI_OK and fmt_type == .object) {
                    readFormatterFromJsObject(env, fmt_prop, &cfg.formatter.options);
                }
            }

            var env_prop: napi_value = null;
            if (napi_get_named_property(env, obj, "env", &env_prop) == NAPI_OK) {
                var env_type: napi_valuetype = .undefined;
                if (napi_typeof(env, env_prop, &env_type) == NAPI_OK and env_type == .object) {
                    readEnvFromJsObject(env, env_prop, &cfg.env);
                }
            }
        }
    }

    const result = linter.lintWithConfig(source, "input.ts", cfg, std.heap.page_allocator) catch return null;
    defer result.deinit(std.heap.page_allocator);

    var result_obj: napi_value = null;
    if (napi_create_object(env, &result_obj) != NAPI_OK) return null;

    var arr: napi_value = null;
    if (napi_create_array_with_length(env, result.diagnostics.len, &arr) != NAPI_OK) return null;

    for (result.diagnostics, 0..) |diag, i| {
        var diag_obj: napi_value = null;
        if (napi_create_object(env, &diag_obj) != NAPI_OK) continue;

        var code_val: napi_value = null;
        if (napi_create_string_utf8(env, diag.rule_code.ptr, diag.rule_code.len, &code_val) == NAPI_OK) {
            _ = napi_set_named_property(env, diag_obj, "ruleCode", code_val);
        }

        var msg_val: napi_value = null;
        if (napi_create_string_utf8(env, diag.message.ptr, diag.message.len, &msg_val) == NAPI_OK) {
            _ = napi_set_named_property(env, diag_obj, "message", msg_val);
        }

        var sev_val: napi_value = null;
        if (napi_create_int64(env, @intCast(@intFromEnum(diag.severity)), &sev_val) == NAPI_OK) {
            _ = napi_set_named_property(env, diag_obj, "severity", sev_val);
        }

        var line_val: napi_value = null;
        if (napi_create_int64(env, @intCast(diag.range.start.line), &line_val) == NAPI_OK) {
            _ = napi_set_named_property(env, diag_obj, "line", line_val);
        }

        var col_val: napi_value = null;
        if (napi_create_int64(env, @intCast(diag.range.start.column), &col_val) == NAPI_OK) {
            _ = napi_set_named_property(env, diag_obj, "column", col_val);
        }

        _ = napi_set_element(env, arr, @intCast(i), diag_obj);
    }

    _ = napi_set_named_property(env, result_obj, "diagnostics", arr);

    if (result.formatted) |formatted| {
        var fmt_val: napi_value = null;
        if (napi_create_string_utf8(env, formatted.ptr, formatted.len, &fmt_val) == NAPI_OK) {
            _ = napi_set_named_property(env, result_obj, "formatted", fmt_val);
        }
    }

    return result_obj;
}

fn readFormatterFromJsObject(env: napi_env, fmt_obj: napi_value, opts: *common.FormatterOptions) void {
    var prop: napi_value = null;
    if (napi_get_named_property(env, fmt_obj, "semi", &prop) == NAPI_OK) {
        var vt: napi_valuetype = .undefined;
        if (napi_typeof(env, prop, &vt) == NAPI_OK and vt == .boolean) {
            _ = napi_get_value_bool(env, prop, &opts.semi);
        }
    }
    if (napi_get_named_property(env, fmt_obj, "singleQuote", &prop) == NAPI_OK) {
        var vt: napi_valuetype = .undefined;
        if (napi_typeof(env, prop, &vt) == NAPI_OK and vt == .boolean) {
            _ = napi_get_value_bool(env, prop, &opts.singleQuote);
        }
    }
    if (napi_get_named_property(env, fmt_obj, "bracketSpacing", &prop) == NAPI_OK) {
        var vt: napi_valuetype = .undefined;
        if (napi_typeof(env, prop, &vt) == NAPI_OK and vt == .boolean) {
            _ = napi_get_value_bool(env, prop, &opts.bracketSpacing);
        }
    }
    if (napi_get_named_property(env, fmt_obj, "useTabs", &prop) == NAPI_OK) {
        var vt: napi_valuetype = .undefined;
        if (napi_typeof(env, prop, &vt) == NAPI_OK and vt == .boolean) {
            _ = napi_get_value_bool(env, prop, &opts.useTabs);
        }
    }
    if (napi_get_named_property(env, fmt_obj, "bracketSameLine", &prop) == NAPI_OK) {
        var vt: napi_valuetype = .undefined;
        if (napi_typeof(env, prop, &vt) == NAPI_OK and vt == .boolean) {
            _ = napi_get_value_bool(env, prop, &opts.bracketSameLine);
        }
    }
    if (napi_get_named_property(env, fmt_obj, "tabWidth", &prop) == NAPI_OK) {
        var val: i64 = 0;
        if (napi_get_value_int64(env, prop, &val) == NAPI_OK and val > 0) {
            opts.tabWidth = @intCast(val);
        }
    }
    if (napi_get_named_property(env, fmt_obj, "printWidth", &prop) == NAPI_OK) {
        var val: i64 = 0;
        if (napi_get_value_int64(env, prop, &val) == NAPI_OK and val > 0) {
            opts.printWidth = @intCast(val);
        }
    }
}

fn readEnvFromJsObject(js_env: napi_env, env_obj: napi_value, lint_env: *common.LintEnvironment) void {
    var prop: napi_value = null;
    if (napi_get_named_property(js_env, env_obj, "node", &prop) == NAPI_OK) {
        var vt: napi_valuetype = .undefined;
        if (napi_typeof(js_env, prop, &vt) == NAPI_OK and vt == .boolean) {
            _ = napi_get_value_bool(js_env, prop, &lint_env.node);
        }
    }
    if (napi_get_named_property(js_env, env_obj, "deno", &prop) == NAPI_OK) {
        var vt: napi_valuetype = .undefined;
        if (napi_typeof(js_env, prop, &vt) == NAPI_OK and vt == .boolean) {
            _ = napi_get_value_bool(js_env, prop, &lint_env.deno);
        }
    }
    if (napi_get_named_property(js_env, env_obj, "bun", &prop) == NAPI_OK) {
        var vt: napi_valuetype = .undefined;
        if (napi_typeof(js_env, prop, &vt) == NAPI_OK and vt == .boolean) {
            _ = napi_get_value_bool(js_env, prop, &lint_env.bun);
        }
    }
}

pub export fn napi_register_module_v1(env: napi_env, exports: napi_value) napi_value {
    var lint_fn: napi_value = null;
    if (napi_create_function(env, "lint", 4, lintFn, null, &lint_fn) == NAPI_OK) {
        _ = napi_set_named_property(env, exports, "lint", lint_fn);
    }
    return exports;
}
