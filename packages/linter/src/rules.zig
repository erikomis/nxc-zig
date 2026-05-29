const std = @import("std");
const common = @import("common");
const ast = @import("ast.zig");

const Arena = ast.Arena;
const NodeId = ast.NodeId;
const Node = ast.Node;

fn getArena(ctx: common.LintContext) error{MissingArena}!*const Arena {
    const ptr = ctx.ast_arena orelse return error.MissingArena;
    return @ptrCast(@alignCast(ptr));
}

fn reportNode(ctx: common.LintContext, rule: common.LintRule, message: []const u8, node: *const Node) !void {
    const span = node.span();
    try ctx.report(rule.code, rule.severity, message, span.start, span.end);
}

fn reportSpan(ctx: common.LintContext, rule: common.LintRule, message: []const u8, start: usize, end: usize) !void {
    try ctx.report(rule.code, rule.severity, message, start, end);
}

fn isCalleeName(arena: *const Arena, call: *const ast.CallExpr, name: []const u8) bool {
    const callee = arena.get(call.callee);
    if (callee.* != .ident) return false;
    return std.mem.eql(u8, callee.ident.name, name);
}

fn isIdentName(arena: *const Arena, id: NodeId, name: []const u8) bool {
    const node = arena.get(id);
    if (node.* != .ident) return false;
    return std.mem.eql(u8, node.ident.name, name);
}

fn isGlobalBuiltin(name: []const u8) bool {
    const globals = [_][]const u8{
        "window",            "global",             "globalThis",           "self",           "document",
        "console",           "process",            "Buffer",               "setTimeout",     "setInterval",
        "clearTimeout",      "clearInterval",      "Math",                 "JSON",           "Promise",
        "Array",             "Object",             "String",               "Number",         "Boolean",
        "Symbol",            "Map",                "Set",                  "WeakMap",        "WeakSet",
        "RegExp",            "Error",              "Date",                 "Function",       "Infinity",
        "NaN",               "undefined",          "null",                 "eval",           "parseInt",
        "parseFloat",        "isNaN",              "isFinite",             "decodeURI",      "decodeURIComponent",
        "encodeURI",         "encodeURIComponent", "BigInt",               "Reflect",        "Proxy",
        "Intl",              "Atomics",            "SharedArrayBuffer",    "Int8Array",      "Uint8Array",
        "Uint8ClampedArray", "Int16Array",         "Uint16Array",          "Int32Array",     "Uint32Array",
        "Float32Array",      "Float64Array",       "BigInt64Array",        "BigUint64Array", "ArrayBuffer",
        "DataView",          "WeakRef",            "FinalizationRegistry", "Iterator",       "Float16Array",
    };
    for (globals) |g| {
        if (std.mem.eql(u8, name, g)) return true;
    }
    return false;
}

fn isNegZero(arena: *const Arena, id: NodeId) bool {
    const n = arena.get(id);
    if (n.* != .unary_expr) return false;
    const u = &n.unary_expr;
    if (u.op != .minus) return false;
    const arg = arena.get(u.argument);
    if (arg.* != .num_lit) return false;
    return std.mem.eql(u8, arg.num_lit.raw, "0");
}

fn isConstant(arena: *const Arena, id: NodeId) bool {
    const n = arena.get(id);
    return switch (n.*) {
        .bool_lit, .num_lit, .str_lit, .null_lit, .undefined_ref => true,
        .unary_expr => |u| (u.op == .bang or u.op == .minus or u.op == .plus) and isConstant(arena, u.argument),
        else => false,
    };
}

fn nodesEqual(arena: *const Arena, a: NodeId, b: NodeId) bool {
    if (a == b) return true;
    const na = arena.get(a);
    const nb = arena.get(b);
    if (!std.mem.eql(u8, @tagName(na.*), @tagName(nb.*))) return false;
    return switch (na.*) {
        .num_lit => std.mem.eql(u8, na.num_lit.raw, nb.num_lit.raw),
        .str_lit => std.mem.eql(u8, na.str_lit.value, nb.str_lit.value),
        .bool_lit => na.bool_lit.value == nb.bool_lit.value,
        .null_lit => true,
        .ident => std.mem.eql(u8, na.ident.name, nb.ident.name),
        .unary_expr => na.unary_expr.op == nb.unary_expr.op and nodesEqual(arena, na.unary_expr.argument, nb.unary_expr.argument),
        .binary_expr => na.binary_expr.op == nb.binary_expr.op and nodesEqual(arena, na.binary_expr.left, nb.binary_expr.left) and nodesEqual(arena, na.binary_expr.right, nb.binary_expr.right),
        else => false,
    };
}

fn scanNodes(ctx: common.LintContext, rule: common.LintRule, comptime visit: fn (*const Arena, NodeId, *const Node, common.LintContext, common.LintRule) anyerror!void) !void {
    const a = try getArena(ctx);
    for (a.nodes.items, 0..) |*node, i| {
        try visit(a, @intCast(i), node, ctx, rule);
    }
}

// ── Rule implementations ──

fn runNoDebugger(_: *const Arena, _: NodeId, node: *const Node, ctx: common.LintContext, rule: common.LintRule) !void {
    if (node.* == .debugger_stmt) {
        try reportNode(ctx, rule, "unexpected debugger statement", node);
    }
}

fn runNoAlert(arena: *const Arena, _: NodeId, node: *const Node, ctx: common.LintContext, rule: common.LintRule) !void {
    if (node.* != .call_expr) return;
    const call = &node.call_expr;
    if (isCalleeName(arena, call, "alert") or
        isCalleeName(arena, call, "confirm") or
        isCalleeName(arena, call, "prompt"))
    {
        try reportNode(ctx, rule, "unexpected alert/confirm/prompt", node);
    }
}

fn runNoEval(arena: *const Arena, _: NodeId, node: *const Node, ctx: common.LintContext, rule: common.LintRule) !void {
    if (node.* != .call_expr) return;
    if (isCalleeName(arena, &node.call_expr, "eval")) {
        try reportNode(ctx, rule, "unexpected eval()", node);
    }
}

fn runNoEmpty(_: *const Arena, _: NodeId, node: *const Node, ctx: common.LintContext, rule: common.LintRule) !void {
    if (node.* != .block) return;
    if (node.block.body.len == 0) {
        try reportNode(ctx, rule, "empty block statement", node);
    }
}

fn runNoCompareNegZero(arena: *const Arena, _: NodeId, node: *const Node, ctx: common.LintContext, rule: common.LintRule) !void {
    if (node.* != .binary_expr) return;
    const bin = &node.binary_expr;
    const op = bin.op;
    if (op != .eq2 and op != .eq3 and op != .neq and op != .neq2 and
        op != .lt and op != .lte and op != .gt and op != .gte) return;
    if (isNegZero(arena, bin.left) or isNegZero(arena, bin.right)) {
        try reportNode(ctx, rule, "do not compare with -0", node);
    }
}

fn runNoCondAssign(arena: *const Arena, _: NodeId, node: *const Node, ctx: common.LintContext, rule: common.LintRule) !void {
    if (node.* != .assign_expr) return;
    const assign = &node.assign_expr;
    if (assign.op != .eq) return;
    for (arena.nodes.items) |*p| {
        const in_cond = switch (p.*) {
            .if_stmt => p.if_stmt.cond == node.span().start,
            .while_stmt => p.while_stmt.cond == node.span().start,
            else => false,
        };
        if (in_cond) {
            try reportNode(ctx, rule, "unexpected assignment in conditional", node);
            return;
        }
    }
}

fn runNoConstantCondition(arena: *const Arena, _: NodeId, node: *const Node, ctx: common.LintContext, rule: common.LintRule) !void {
    if (node.* != .binary_expr) return;
    const bin = &node.binary_expr;
    if (isConstant(arena, bin.left) and isConstant(arena, bin.right)) {
        try reportNode(ctx, rule, "unexpected constant condition", node);
    }
}

fn runNoControlRegex(_: *const Arena, _: NodeId, node: *const Node, ctx: common.LintContext, rule: common.LintRule) !void {
    if (node.* != .regex_lit) return;
    const raw = node.regex_lit.raw;
    for (raw) |c| {
        if (c < 0x20 or c == 0x7f) {
            try reportNode(ctx, rule, "unexpected control character in regex", node);
            return;
        }
    }
}

fn runNoDeleteVar(arena: *const Arena, _: NodeId, node: *const Node, ctx: common.LintContext, rule: common.LintRule) !void {
    if (node.* != .unary_expr) return;
    if (node.unary_expr.op != .delete) return;
    const arg = arena.get(node.unary_expr.argument);
    if (arg.* == .ident) {
        try reportNode(ctx, rule, "unexpected delete of variable", node);
    }
}

fn runNoDupeKeys(arena: *const Arena, _: NodeId, node: *const Node, ctx: common.LintContext, rule: common.LintRule) !void {
    if (node.* != .object_expr) return;
    const obj = &node.object_expr;
    var seen = std.StringHashMap(NodeId).init(ctx.alloc);
    defer seen.deinit();
    for (obj.props) |prop| {
        const key_node = switch (prop) {
            .kv => |kv| kv.key,
            .method => |m| m.key,
            .shorthand => |s| s,
            .spread => continue,
        };
        const kn = arena.get(key_node);
        const key_name = switch (kn.*) {
            .ident => |id| id.name,
            .str_lit => |s| s.value,
            else => continue,
        };
        if (seen.get(key_name)) |_| {
            try reportNode(ctx, rule, "duplicate key in object literal", kn);
        } else {
            try seen.put(key_name, key_node);
        }
    }
}

fn runNoDuplicateCase(arena: *const Arena, _: NodeId, node: *const Node, ctx: common.LintContext, rule: common.LintRule) !void {
    if (node.* != .switch_stmt) return;
    const sw = &node.switch_stmt;
    for (sw.cases, 0..) |case, i| {
        const cond = case.cond orelse continue;
        for (sw.cases[i + 1 ..]) |other| {
            const other_cond = other.cond orelse continue;
            if (nodesEqual(arena, cond, other_cond)) {
                try reportNode(ctx, rule, "duplicate case label", arena.get(cond));
            }
        }
    }
}

fn runNoEmptyPattern(_: *const Arena, _: NodeId, node: *const Node, ctx: common.LintContext, rule: common.LintRule) !void {
    if (node.* == .object_pat and node.object_pat.props.len == 0 and node.object_pat.rest == null) {
        try reportNode(ctx, rule, "unexpected empty destructuring pattern", node);
    }
    if (node.* == .array_pat and node.array_pat.elements.len == 0 and node.array_pat.rest == null) {
        try reportNode(ctx, rule, "unexpected empty destructuring pattern", node);
    }
}

fn runNoExAssign(arena: *const Arena, _: NodeId, node: *const Node, ctx: common.LintContext, rule: common.LintRule) !void {
    if (node.* != .assign_expr) return;
    const left = arena.get(node.assign_expr.left);
    if (left.* == .ident) {
        const name = left.ident.name;
        if (std.mem.eql(u8, name, "catch") or std.mem.startsWith(u8, name, "err")) {
            var in_catch = false;
            for (arena.nodes.items) |*p| {
                if (p.* != .try_stmt) continue;
                if (p.try_stmt.handler) |h| {
                    if (h.param != null and arena.get(h.param.?).* == .ident and
                        std.mem.eql(u8, arena.get(h.param.?).ident.name, name))
                    {
                        in_catch = true;
                    }
                }
            }
            if (in_catch) {
                try reportNode(ctx, rule, "unexpected reassignment of catch parameter", node);
            }
        }
    }
}

fn runNoExtraBooleanCast(arena: *const Arena, _: NodeId, node: *const Node, ctx: common.LintContext, rule: common.LintRule) !void {
    if (node.* != .unary_expr) return;
    if (node.unary_expr.op != .bang) return;
    const arg = arena.get(node.unary_expr.argument);
    if (arg.* == .unary_expr and arg.unary_expr.op == .bang) {
        try reportNode(ctx, rule, "unexpected double boolean cast", node);
    }
}

fn runNoFuncAssign(arena: *const Arena, _: NodeId, node: *const Node, ctx: common.LintContext, rule: common.LintRule) !void {
    if (node.* != .assign_expr) return;
    const left = arena.get(node.assign_expr.left);
    if (left.* != .ident) return;
    const name = left.ident.name;
    for (arena.nodes.items) |*p| {
        if (p.* == .fn_decl and p.fn_decl.id != null) {
            const fn_id = arena.get(p.fn_decl.id.?);
            if (fn_id.* == .ident and std.mem.eql(u8, fn_id.ident.name, name)) {
                try reportNode(ctx, rule, "unexpected reassignment of function declaration", node);
            }
        }
    }
}

fn runNoGlobals(_: *const Arena, _: NodeId, node: *const Node, ctx: common.LintContext, rule: common.LintRule) !void {
    if (node.* != .assign_expr) return;
    const arena = try getArena(ctx);
    const left = arena.get(node.assign_expr.left);
    if (left.* == .member_expr) return;
    if (left.* != .ident) return;
    if (isGlobalBuiltin(left.ident.name)) {
        try reportNode(ctx, rule, "unexpected assignment to global variable", node);
    }
}

fn runNoNewNativeNonconstructor(arena: *const Arena, _: NodeId, node: *const Node, ctx: common.LintContext, rule: common.LintRule) !void {
    if (node.* != .new_expr) return;
    const callee = arena.get(node.new_expr.callee);
    if (callee.* != .ident) return;
    const name = callee.ident.name;
    const non_constructors = [_][]const u8{ "Symbol", "BigInt" };
    for (non_constructors) |nc| {
        if (std.mem.eql(u8, name, nc)) {
            try reportNode(ctx, rule, "unexpected new with non-constructor", node);
            return;
        }
    }
}

fn runNoNonoctalDecimalEscape(_: *const Arena, _: NodeId, node: *const Node, ctx: common.LintContext, rule: common.LintRule) !void {
    if (node.* != .str_lit) return;
    const val = node.str_lit.value;
    var i: usize = 0;
    while (i < val.len) : (i += 1) {
        if (val[i] == '\\' and i + 1 < val.len) {
            if (val[i + 1] >= '0' and val[i + 1] <= '9') {
                try reportSpan(ctx, rule, "nonoctal decimal escape", node.span().start + i, node.span().start + i + 2);
                return;
            }
        }
    }
}

fn runNoObjCalls(arena: *const Arena, _: NodeId, node: *const Node, ctx: common.LintContext, rule: common.LintRule) !void {
    if (node.* != .call_expr) return;
    const callee = arena.get(node.call_expr.callee);
    if (callee.* != .ident) return;
    const name = callee.ident.name;
    if (std.mem.eql(u8, name, "Math") or std.mem.eql(u8, name, "JSON") or std.mem.eql(u8, name, "Reflect") or std.mem.eql(u8, name, "Atomics") or std.mem.eql(u8, name, "BigInt")) {
        try reportNode(ctx, rule, "unexpected call to global object", node);
    }
}

fn runNoOctal(_: *const Arena, _: NodeId, node: *const Node, ctx: common.LintContext, rule: common.LintRule) !void {
    if (node.* != .num_lit) return;
    const raw = node.num_lit.raw;
    if (raw.len > 1 and raw[0] == '0' and raw[1] >= '0' and raw[1] <= '7') {
        try reportNode(ctx, rule, "unexpected octal literal", node);
    }
}

fn runNoPrototypeBuiltins(arena: *const Arena, _: NodeId, node: *const Node, ctx: common.LintContext, rule: common.LintRule) !void {
    if (node.* != .call_expr) return;
    const callee = arena.get(node.call_expr.callee);
    if (callee.* != .member_expr) return;
    const prop = arena.get(callee.member_expr.prop);
    if (prop.* != .ident) return;
    const prop_name = prop.ident.name;
    if (std.mem.eql(u8, prop_name, "hasOwnProperty") or
        std.mem.eql(u8, prop_name, "isPrototypeOf") or
        std.mem.eql(u8, prop_name, "propertyIsEnumerable"))
    {
        try reportNode(ctx, rule, "unexpected call to Object.prototype method", node);
    }
}

fn runNoSelfAssign(arena: *const Arena, _: NodeId, node: *const Node, ctx: common.LintContext, rule: common.LintRule) !void {
    if (node.* != .assign_expr) return;
    const assign = &node.assign_expr;
    if (assign.op != .eq) return;
    if (nodesEqual(arena, assign.left, assign.right)) {
        try reportNode(ctx, rule, "unexpected self-assignment", node);
    }
}

fn runNoSparseArrays(_: *const Arena, _: NodeId, node: *const Node, ctx: common.LintContext, rule: common.LintRule) !void {
    if (node.* != .array_expr) return;
    for (node.array_expr.elements) |elem| {
        if (elem == null) {
            try reportNode(ctx, rule, "unexpected sparse array", node);
            return;
        }
    }
}

fn runNoUnsafeNegation(arena: *const Arena, _: NodeId, node: *const Node, ctx: common.LintContext, rule: common.LintRule) !void {
    if (node.* != .unary_expr) return;
    if (node.unary_expr.op != .bang) return;
    const arg = arena.get(node.unary_expr.argument);
    if (arg.* != .binary_expr) return;
    const op = arg.binary_expr.op;
    switch (op) {
        .lt, .lte, .gt, .gte, .eq2, .eq3, .neq, .neq2, .in, .instanceof => {
            try reportNode(ctx, rule, "unexpected negation of relational operator", node);
        },
        else => {},
    }
}

fn runNoUnsafeOptionalChaining(arena: *const Arena, _: NodeId, node: *const Node, ctx: common.LintContext, rule: common.LintRule) !void {
    if (node.* != .call_expr) return;
    const call = &node.call_expr;
    if (!call.optional) return;
    const callee = arena.get(call.callee);
    if (callee.* == .call_expr) {
        try reportNode(ctx, rule, "unexpected optional chaining on call expression", node);
    }
}

fn runNoUselessCatch(arena: *const Arena, _: NodeId, node: *const Node, ctx: common.LintContext, rule: common.LintRule) !void {
    if (node.* != .try_stmt) return;
    const handler = node.try_stmt.handler orelse return;
    const block = arena.get(handler.body);
    if (block.* != .block) return;
    if (block.block.body.len != 1) return;
    const stmt = arena.get(block.block.body[0]);
    if (stmt.* != .throw_stmt) return;
    const throw_arg = arena.get(stmt.throw_stmt.argument);
    if (throw_arg.* != .ident) return;
    if (handler.param == null) return;
    const param_node = arena.get(handler.param.?);
    if (param_node.* != .ident) return;
    if (std.mem.eql(u8, param_node.ident.name, throw_arg.ident.name)) {
        try reportNode(ctx, rule, "unexpected useless catch", node);
    }
}

fn runRequireYield(arena: *const Arena, _: NodeId, node: *const Node, ctx: common.LintContext, rule: common.LintRule) !void {
    if (node.* != .fn_decl) return;
    if (!node.fn_decl.is_generator) return;
    const body = arena.get(node.fn_decl.body);
    if (body.* != .block) return;
    var has_yield = false;
    for (body.block.body) |stmt_id| {
        if (arena.get(stmt_id).* == .yield_expr) {
            has_yield = true;
            break;
        }
    }
    if (!has_yield) {
        try reportNode(ctx, rule, "generator function should have yield", node);
    }
}

fn runUseIsNaN(arena: *const Arena, _: NodeId, node: *const Node, ctx: common.LintContext, rule: common.LintRule) !void {
    if (node.* != .binary_expr) return;
    const bin = &node.binary_expr;
    if (bin.op != .eq2 and bin.op != .eq3 and bin.op != .neq and bin.op != .neq2) return;
    if (isIdentName(arena, bin.left, "NaN") or isIdentName(arena, bin.right, "NaN")) {
        try reportNode(ctx, rule, "use isNaN() instead of comparing with NaN", node);
    }
}

fn runValidTypeof(arena: *const Arena, _: NodeId, node: *const Node, ctx: common.LintContext, rule: common.LintRule) !void {
    if (node.* != .binary_expr) return;
    const bin = &node.binary_expr;
    if (bin.op != .eq2 and bin.op != .eq3 and bin.op != .neq and bin.op != .neq2) return;
    const left_typeof = arena.get(bin.left).* == .unary_expr and arena.get(bin.left).unary_expr.op == .typeof;
    const right_typeof = arena.get(bin.right).* == .unary_expr and arena.get(bin.right).unary_expr.op == .typeof;
    if (!left_typeof and !right_typeof) return;
    const str_node = if (left_typeof) bin.right else bin.left;
    const str_n = arena.get(str_node);
    if (str_n.* != .str_lit) return;
    const str_val = str_n.str_lit.value;
    const valid = std.mem.eql(u8, str_val, "undefined") or
        std.mem.eql(u8, str_val, "object") or
        std.mem.eql(u8, str_val, "boolean") or
        std.mem.eql(u8, str_val, "number") or
        std.mem.eql(u8, str_val, "string") or
        std.mem.eql(u8, str_val, "function") or
        std.mem.eql(u8, str_val, "symbol") or
        std.mem.eql(u8, str_val, "bigint");
    if (!valid) {
        try reportNode(ctx, rule, "unexpected typeof comparison with invalid string", str_n);
    }
}

fn runNoShadowRestrictedNames(_: *const Arena, _: NodeId, node: *const Node, ctx: common.LintContext, rule: common.LintRule) !void {
    const name = switch (node.*) {
        .ident => node.ident.name,
        else => return,
    };
    const restricted = [_][]const u8{
        "arguments", "NaN",     "Infinity",   "undefined", "eval",
        "class",     "delete",  "enum",       "export",    "extends",
        "import",    "super",   "implements", "interface", "let",
        "package",   "private", "protected",  "public",    "static",
        "yield",     "await",
    };
    for (restricted) |r| {
        if (std.mem.eql(u8, name, r)) {
            try reportNode(ctx, rule, "unexpected shadow of restricted name", node);
            return;
        }
    }
}

fn runNoUnreachable(arena: *const Arena, _: NodeId, node: *const Node, ctx: common.LintContext, rule: common.LintRule) !void {
    if (node.* != .block) return;
    var unreachable_seen = false;
    for (node.block.body) |stmt_id| {
        const stmt = arena.get(stmt_id);
        if (stmt.* == .return_stmt or stmt.* == .throw_stmt) {
            unreachable_seen = true;
        } else if (unreachable_seen and stmt.* != .empty_stmt) {
            if (stmt.* == .fn_decl or stmt.* == .var_decl) continue;
            try reportNode(ctx, rule, "unreachable code", stmt);
            return;
        }
    }
}

fn runNoUnsafeFinally(arena: *const Arena, _: NodeId, node: *const Node, ctx: common.LintContext, rule: common.LintRule) !void {
    if (node.* != .try_stmt) return;
    const fin = node.try_stmt.finalizer orelse return;
    const block = arena.get(fin);
    if (block.* != .block) return;
    for (block.block.body) |stmt_id| {
        const stmt = arena.get(stmt_id);
        if (stmt.* == .return_stmt or stmt.* == .throw_stmt or
            stmt.* == .break_continue or
            (stmt.* == .expr_stmt and arena.get(stmt.expr_stmt.expr).* == .yield_expr))
        {
            try reportNode(ctx, rule, "unexpected control flow in finally block", stmt);
        }
    }
}

fn runNoImportAssign(arena: *const Arena, _: NodeId, node: *const Node, ctx: common.LintContext, rule: common.LintRule) !void {
    if (node.* != .assign_expr) return;
    const left = arena.get(node.assign_expr.left);
    if (left.* != .ident) return;
    const name = left.ident.name;
    for (arena.nodes.items) |*p| {
        if (p.* != .import_decl) continue;
        for (p.import_decl.specifiers) |spec| {
            const local = arena.get(spec.local);
            if (local.* == .ident and std.mem.eql(u8, local.ident.name, name)) {
                try reportNode(ctx, rule, "unexpected assignment to imported binding", node);
                return;
            }
        }
    }
}

fn runNoConstAssign(arena: *const Arena, _: NodeId, node: *const Node, ctx: common.LintContext, rule: common.LintRule) !void {
    if (node.* != .assign_expr) return;
    const left = arena.get(node.assign_expr.left);
    if (left.* != .ident) return;
    const name = left.ident.name;
    for (arena.nodes.items) |*p| {
        if (p.* != .var_decl) continue;
        if (p.var_decl.kind != .@"const" and p.var_decl.kind != .using) continue;
        for (p.var_decl.declarators) |decl| {
            const decl_id = arena.get(decl.id);
            if (decl_id.* == .ident and std.mem.eql(u8, decl_id.ident.name, name)) {
                try reportNode(ctx, rule, "unexpected assignment to const variable", node);
                return;
            }
        }
    }
}

fn runNoClassAssign(arena: *const Arena, _: NodeId, node: *const Node, ctx: common.LintContext, rule: common.LintRule) !void {
    if (node.* != .assign_expr) return;
    const left = arena.get(node.assign_expr.left);
    if (left.* != .ident) return;
    const name = left.ident.name;
    for (arena.nodes.items) |*p| {
        if (p.* != .class_decl) continue;
        if (p.class_decl.id == null) continue;
        const cid = arena.get(p.class_decl.id.?);
        if (cid.* == .ident and std.mem.eql(u8, cid.ident.name, name)) {
            try reportNode(ctx, rule, "unexpected assignment to class declaration", node);
            return;
        }
    }
}

fn runNoDupeArgs(arena: *const Arena, _: NodeId, node: *const Node, ctx: common.LintContext, rule: common.LintRule) !void {
    const params = switch (node.*) {
        .fn_decl => node.fn_decl.params,
        .fn_expr => node.fn_expr.params,
        .arrow_fn => node.arrow_fn.params,
        else => return,
    };
    var seen = std.StringHashMap(void).init(ctx.alloc);
    defer seen.deinit();
    for (params) |p_id| {
        const p = arena.get(p_id);
        if (p.* != .ident) continue;
        if (seen.contains(p.ident.name)) {
            try reportNode(ctx, rule, "duplicate parameter name", p);
            return;
        }
        try seen.put(p.ident.name, {});
    }
}

fn runNoDupeClassMembers(arena: *const Arena, _: NodeId, node: *const Node, ctx: common.LintContext, rule: common.LintRule) !void {
    if (node.* != .class_decl and node.* != .class_expr) return;
    const members = switch (node.*) {
        .class_decl => node.class_decl.body,
        .class_expr => node.class_expr.body,
        else => return,
    };
    var seen = std.StringHashMap(NodeId).init(ctx.alloc);
    defer seen.deinit();
    for (members) |member| {
        if (member.kind == .static_block or member.kind == .auto_accessor) continue;
        const key_node = arena.get(member.key);
        const key_name = switch (key_node.*) {
            .ident => key_node.ident.name,
            .str_lit => key_node.str_lit.value,
            else => continue,
        };
        if (seen.get(key_name)) |_| {
            try reportNode(ctx, rule, "duplicate class member", key_node);
        } else {
            try seen.put(key_name, member.key);
        }
    }
}

fn runNoDupeElseIf(arena: *const Arena, _: NodeId, node: *const Node, ctx: common.LintContext, rule: common.LintRule) !void {
    if (node.* != .if_stmt) return;
    var current = &node.if_stmt;
    while (current.alternate) |alt_id| {
        const alt = arena.get(alt_id);
        if (alt.* != .if_stmt) return;
        if (alt.if_stmt.cond != current.cond and nodesEqual(arena, alt.if_stmt.cond, current.cond)) {
            try reportNode(ctx, rule, "duplicate condition in if-else-if chain", arena.get(alt.if_stmt.cond));
            return;
        }
        current = &alt.if_stmt;
    }
}

fn runNoCaseDeclarations(arena: *const Arena, _: NodeId, node: *const Node, ctx: common.LintContext, rule: common.LintRule) !void {
    if (node.* != .switch_stmt) return;
    for (node.switch_stmt.cases) |case| {
        for (case.body) |stmt_id| {
            const stmt = arena.get(stmt_id);
            if (stmt.* == .var_decl) {
                try reportNode(ctx, rule, "unexpected lexical declaration in case block", stmt);
            }
        }
    }
}

fn runNoAsyncPromiseExecutor(arena: *const Arena, _: NodeId, node: *const Node, ctx: common.LintContext, rule: common.LintRule) !void {
    if (node.* != .new_expr) return;
    if (!isCalleeName(arena, &.{ .callee = node.new_expr.callee, .type_args = &.{}, .args = node.new_expr.args, .optional = false, .span = undefined }, "Promise")) return;
    if (node.new_expr.args.len == 0) return;
    const executor = arena.get(node.new_expr.args[0].expr);
    const is_async = switch (executor.*) {
        .arrow_fn => executor.arrow_fn.is_async,
        .fn_expr => executor.fn_expr.is_async,
        else => false,
    };
    if (is_async) {
        try reportNode(ctx, rule, "unexpected async function in Promise executor", executor);
    }
}

fn runNoConstantBinaryExpression(arena: *const Arena, _: NodeId, node: *const Node, ctx: common.LintContext, rule: common.LintRule) !void {
    if (node.* != .binary_expr) return;
    const bin = &node.binary_expr;
    if (isConstant(arena, bin.left) and isConstant(arena, bin.right) and bin.op != .comma) {
        try reportNode(ctx, rule, "unexpected constant binary expression", node);
    }
}

fn runForDirection(arena: *const Arena, _: NodeId, node: *const Node, ctx: common.LintContext, rule: common.LintRule) !void {
    if (node.* != .for_stmt) return;
    const stmt = &node.for_stmt;
    if (stmt.kind != .plain) return;
    if (stmt.update == null or stmt.cond == null) return;
    const cond = arena.get(stmt.cond.?);
    if (cond.* != .binary_expr) return;
    const bin = &cond.binary_expr;
    const left = arena.get(bin.left);
    const right = arena.get(bin.right);
    if (left.* != .ident or right.* != .num_lit) return;
    const var_name = left.ident.name;
    const update = arena.get(stmt.update.?);
    if (update.* != .update_expr) return;
    const up_arg = arena.get(update.update_expr.argument);
    if (up_arg.* != .ident) return;
    if (!std.mem.eql(u8, up_arg.ident.name, var_name)) return;
    if (bin.op == .lt or bin.op == .lte) {
        if (update.update_expr.op == .minus2) {
            try reportNode(ctx, rule, "loop updates in wrong direction", update);
        }
    }
    if (bin.op == .gt or bin.op == .gte) {
        if (update.update_expr.op == .plus2) {
            try reportNode(ctx, rule, "loop updates in wrong direction", update);
        }
    }
}

fn collectPatternIdents(arena: *const Arena, node_id: NodeId, names: *std.ArrayListUnmanaged([]const u8)) void {
    const n = arena.get(node_id);
    switch (n.*) {
        .ident => names.append(arena.alloc, n.ident.name) catch {},
        .assign_pat => collectPatternIdents(arena, n.assign_pat.left, names),
        .object_pat => {
            for (n.object_pat.props) |prop| {
                switch (prop) {
                    .assign => |a| {
                        if (a.value) |val| {
                            collectPatternIdents(arena, val, names);
                        } else {
                            collectPatternIdents(arena, a.key, names);
                        }
                    },
                    .rest => |r| collectPatternIdents(arena, r, names),
                }
            }
            if (n.object_pat.rest) |r| collectPatternIdents(arena, r, names);
        },
        .array_pat => {
            for (n.array_pat.elements) |elem| {
                if (elem) |e| collectPatternIdents(arena, e, names);
            }
            if (n.array_pat.rest) |r| collectPatternIdents(arena, r, names);
        },
        else => {},
    }
}

fn patternContains(arena: *const Arena, node_id: NodeId, name: []const u8) bool {
    var names = std.ArrayListUnmanaged([]const u8).empty;
    defer names.deinit(arena.alloc);
    collectPatternIdents(arena, node_id, &names);
    for (names.items) |n| {
        if (std.mem.eql(u8, n, name)) return true;
    }
    return false;
}

fn runNoUndef(arena: *const Arena, id: NodeId, node: *const Node, ctx: common.LintContext, rule: common.LintRule) !void {
    if (node.* != .ident) return;
    const name = node.ident.name;
    if (isGlobalBuiltin(name)) return;
    if (std.mem.startsWith(u8, name, "_") or std.mem.eql(u8, name, "arguments")) return;
    if (envSupports(ctx.env, name)) return;
    if (isMemberProp(arena, id)) return;
    if (isObjectKey(arena, id)) return;
    var found = false;
    for (arena.nodes.items) |*p| {
        if (p.* == .var_decl) {
            for (p.var_decl.declarators) |decl| {
                const decl_id_node = arena.get(decl.id);
                if (decl_id_node.* == .ident and std.mem.eql(u8, decl_id_node.ident.name, name)) {
                    found = true;
                    break;
                }
                if (patternContains(arena, decl.id, name)) {
                    found = true;
                    break;
                }
            }
            if (found) break;
        }
        if (p.* == .fn_decl) {
            if (p.fn_decl.id != null) {
                const fn_id = arena.get(p.fn_decl.id.?);
                if (fn_id.* == .ident and std.mem.eql(u8, fn_id.ident.name, name)) {
                    found = true;
                    break;
                }
            }
            for (p.fn_decl.params) |param_id| {
                if (patternContains(arena, param_id, name)) {
                    found = true;
                    break;
                }
            }
            if (found) break;
        }
        if (p.* == .arrow_fn) {
            for (p.arrow_fn.params) |param_id| {
                if (patternContains(arena, param_id, name)) {
                    found = true;
                    break;
                }
            }
            if (found) break;
        }
        if (p.* == .fn_expr) {
            if (p.fn_expr.id != null) {
                const fn_id = arena.get(p.fn_expr.id.?);
                if (fn_id.* == .ident and std.mem.eql(u8, fn_id.ident.name, name)) {
                    found = true;
                    break;
                }
            }
            for (p.fn_expr.params) |param_id| {
                if (patternContains(arena, param_id, name)) {
                    found = true;
                    break;
                }
            }
            if (found) break;
        }
        if (p.* == .class_decl and p.class_decl.id != null) {
            const cls_id = arena.get(p.class_decl.id.?);
            if (cls_id.* == .ident and std.mem.eql(u8, cls_id.ident.name, name)) {
                found = true;
                break;
            }
        }
        if (p.* == .import_decl) {
            for (p.import_decl.specifiers) |spec| {
                const local = arena.get(spec.local);
                if (local.* == .ident and std.mem.eql(u8, local.ident.name, name)) {
                    found = true;
                    break;
                }
            }
            if (found) break;
        }
        if (p.* == .try_stmt and p.try_stmt.handler != null) {
            const handler = &p.try_stmt.handler.?;
            if (handler.param) |param_id| {
                if (patternContains(arena, param_id, name)) {
                    found = true;
                    break;
                }
            }
        }
    }
    if (!found) {
        const msg = try std.fmt.allocPrint(ctx.alloc, "'{s}' is not defined", .{name});
        defer ctx.alloc.free(msg);
        try reportNode(ctx, rule, msg, node);
    }
}

fn isMemberProp(arena: *const Arena, id: NodeId) bool {
    for (arena.nodes.items) |*p| {
        if (p.* == .member_expr and p.member_expr.prop == id) return true;
    }
    return false;
}

fn isObjectKey(arena: *const Arena, id: NodeId) bool {
    for (arena.nodes.items) |*p| {
        if (p.* == .object_expr) {
            for (p.object_expr.props) |prop| {
                switch (prop) {
                    .kv => |kv| if (!kv.computed and kv.key == id) return true,
                    .method => |m| if (!m.computed and m.key == id) return true,
                    .shorthand => {},
                    .spread => {},
                }
            }
        }
        if (p.* == .class_decl) {
            for (p.class_decl.body) |member| {
                if (!member.is_computed and member.key == id) return true;
            }
        }
        if (p.* == .class_expr) {
            for (p.class_expr.body) |member| {
                if (!member.is_computed and member.key == id) return true;
            }
        }
    }
    return false;
}

fn envSupports(env: common.LintEnvironment, name: []const u8) bool {
    if (env.node) {
        const node_globals = [_][]const u8{
            "require",     "module",    "exports",    "__dirname",    "__filename",
            "setImmediate", "clearImmediate",
        };
        for (node_globals) |g| {
            if (std.mem.eql(u8, name, g)) return true;
        }
    }
    if (env.deno) {
        const deno_globals = [_][]const u8{
            "Deno",
        };
        for (deno_globals) |g| {
            if (std.mem.eql(u8, name, g)) return true;
        }
    }
    if (env.bun) {
        const bun_globals = [_][]const u8{
            "Bun",
        };
        for (bun_globals) |g| {
            if (std.mem.eql(u8, name, g)) return true;
        }
    }
    return false;
}

fn runNoUnusedVars(arena: *const Arena, node_id: NodeId, node: *const Node, ctx: common.LintContext, rule: common.LintRule) !void {
    if (node.* != .var_decl) return;
    for (arena.nodes.items) |*other| {
        if (other.* == .export_decl) switch (other.export_decl.kind) {
            .decl => |decl_id| if (decl_id == node_id) return,
            else => {},
        };
    }
    for (node.var_decl.declarators) |decl| {
        const decl_id = arena.get(decl.id);
        if (decl_id.* != .ident) continue;
        const name = decl_id.ident.name;
        if (std.mem.startsWith(u8, name, "_")) continue;
        var used = false;
        for (arena.nodes.items) |*p| {
            if (p.* != .ident) continue;
            if (@intFromPtr(p) == @intFromPtr(decl_id)) continue;
            if (std.mem.eql(u8, p.ident.name, name)) {
                used = true;
                break;
            }
        }
        if (!used) {
            const msg = try std.fmt.allocPrint(ctx.alloc, "'{s}' is defined but never used", .{name});
            defer ctx.alloc.free(msg);
            try reportNode(ctx, rule, msg, decl_id);
        }
    }
}

fn runNoFallthrough(arena: *const Arena, _: NodeId, node: *const Node, ctx: common.LintContext, rule: common.LintRule) !void {
    if (node.* != .switch_stmt) return;
    const cases = node.switch_stmt.cases;
    for (cases, 0..) |case, i| {
        if (i == cases.len - 1) break;
        if (case.body.len == 0) {
            if (case.cond) |cond| {
                try reportNode(ctx, rule, "unexpected fallthrough in switch", arena.get(cond));
            }
            continue;
        }
        const last = arena.get(case.body[case.body.len - 1]);
        if (last.* != .break_continue or !last.break_continue.is_break) {
            if (last.* != .return_stmt and last.* != .throw_stmt) {
                try reportNode(ctx, rule, "unexpected fallthrough in switch", last);
            }
        }
    }
}

fn runNoEmptyStaticBlock(arena: *const Arena, _: NodeId, node: *const Node, ctx: common.LintContext, rule: common.LintRule) !void {
    if (node.* != .class_decl and node.* != .class_expr) return;
    const members = switch (node.*) {
        .class_decl => node.class_decl.body,
        .class_expr => node.class_expr.body,
        else => return,
    };
    for (members) |member| {
        if (member.kind == .static_block and member.value != null) {
            const block_node = arena.get(member.value.?);
            if (block_node.* == .block and block_node.block.body.len == 0) {
                try reportNode(ctx, rule, "unexpected empty static block", block_node);
            }
        }
    }
}

fn runNoSelfCompare(arena: *const Arena, _: NodeId, node: *const Node, ctx: common.LintContext, rule: common.LintRule) !void {
    if (node.* != .binary_expr) return;
    const bin = &node.binary_expr;
    switch (bin.op) {
        .eq2, .eq3, .neq, .neq2, .lt, .lte, .gt, .gte => {
            if (nodesEqual(arena, bin.left, bin.right)) {
                try reportNode(ctx, rule, "unexpected self-comparison", node);
            }
        },
        else => {},
    }
}

fn runNoTemplateCurlyInString(_: *const Arena, _: NodeId, node: *const Node, ctx: common.LintContext, rule: common.LintRule) !void {
    if (node.* != .str_lit) return;
    if (std.mem.indexOf(u8, node.str_lit.value, "${")) |idx| {
        try reportSpan(ctx, rule, "unexpected template placeholder in string", node.span().start + idx, node.span().start + idx + 2);
    }
}

fn runNoAwaitInLoop(arena: *const Arena, _: NodeId, node: *const Node, ctx: common.LintContext, rule: common.LintRule) !void {
    if (node.* != .for_stmt and node.* != .while_stmt) return;
    const loop_span = node.span();
    for (arena.nodes.items) |*p| {
        if (p.* == .await_expr) {
            const await_span = p.span();
            if (await_span.start >= loop_span.start and await_span.end <= loop_span.end) {
                try reportNode(ctx, rule, "unexpected await inside loop", p);
            }
        }
    }
}

fn runNoPromiseExecutorReturn(arena: *const Arena, _: NodeId, node: *const Node, ctx: common.LintContext, rule: common.LintRule) !void {
    if (node.* != .new_expr) return;
    if (!isCalleeName(arena, &.{ .callee = node.new_expr.callee, .type_args = &.{}, .args = node.new_expr.args, .optional = false, .span = undefined }, "Promise")) return;
    if (node.new_expr.args.len == 0) return;
    const fn_node = arena.get(node.new_expr.args[0].expr);
    const body_id = switch (fn_node.*) {
        .fn_expr => fn_node.fn_expr.body,
        .arrow_fn => fn_node.arrow_fn.body,
        else => return,
    };
    const body = arena.get(body_id);
    if (body.* != .block) return;
    for (body.block.body) |stmt_id| {
        const stmt = arena.get(stmt_id);
        if (stmt.* == .return_stmt and stmt.return_stmt.argument != null) {
            try reportNode(ctx, rule, "unexpected return in Promise executor", stmt);
        }
    }
}

fn runNoInnerDeclarations(arena: *const Arena, _: NodeId, node: *const Node, ctx: common.LintContext, rule: common.LintRule) !void {
    if (node.* != .block) return;
    for (node.block.body) |stmt_id| {
        const stmt = arena.get(stmt_id);
        if (stmt.* == .fn_decl) {
            try reportNode(ctx, rule, "unexpected function declaration in nested block", stmt);
        }
    }
}

fn runPreserveCaughtError(arena: *const Arena, _: NodeId, node: *const Node, ctx: common.LintContext, rule: common.LintRule) !void {
    if (node.* != .try_stmt) return;
    const handler = node.try_stmt.handler orelse return;
    const param = handler.param orelse return;
    const param_node = arena.get(param);
    if (param_node.* != .ident) return;
    const name = param_node.ident.name;
    const body = arena.get(handler.body);
    if (body.* != .block) return;
    for (body.block.body) |stmt_id| {
        const stmt = arena.get(stmt_id);
        if (stmt.* == .assign_expr) {
            const left = arena.get(stmt.assign_expr.left);
            if (left.* == .ident and std.mem.eql(u8, left.ident.name, name)) {
                try reportNode(ctx, rule, "unexpected reassignment of catch parameter", stmt);
            }
        }
    }
}

fn runNoVar(_: *const Arena, _: NodeId, node: *const Node, ctx: common.LintContext, rule: common.LintRule) !void {
    if (node.* != .var_decl) return;
    if (node.var_decl.kind == .@"var") {
        try reportNode(ctx, rule, "unexpected var, use let or const instead", node);
    }
}

fn runPreferTemplate(arena: *const Arena, _: NodeId, node: *const Node, ctx: common.LintContext, rule: common.LintRule) !void {
    if (node.* != .binary_expr) return;
    if (node.binary_expr.op != .plus) return;
    const left = arena.get(node.binary_expr.left);
    const right = arena.get(node.binary_expr.right);
    if (left.* == .str_lit and right.* == .str_lit) return;
    if (left.* != .str_lit and right.* != .str_lit) return;
    try reportNode(ctx, rule, "use template literals instead of string concatenation", node);
}

fn fixPreferTemplate(arena: *const Arena, _: NodeId, node: *const Node, ctx: common.LintContext, _: common.LintRule) !void {
    if (node.* != .binary_expr) return;
    if (node.binary_expr.op != .plus) return;
    const left = arena.get(node.binary_expr.left);
    const right = arena.get(node.binary_expr.right);
    if (left.* == .str_lit and right.* == .str_lit) return;
    if (left.* != .str_lit and right.* != .str_lit) return;

    const sp = node.span();
    const source = ctx.source;

    var parts = std.ArrayListUnmanaged([]const u8).empty;
    defer parts.deinit(ctx.alloc);

    try parts.append(ctx.alloc, "`");

    // Walk the binary expression tree collecting string parts and expressions.
    // We handle simple `str + expr` / `expr + str` patterns. Nested `+` is
    // handled recursively.
    try collectTemplateParts(arena, node.binary_expr.left, source, &parts, ctx.alloc);
    try collectTemplateParts(arena, node.binary_expr.right, source, &parts, ctx.alloc);

    try parts.append(ctx.alloc, "`");

    var total: usize = 0;
    for (parts.items) |p| total += p.len;
    const replacement = try ctx.alloc.alloc(u8, total);
    var offset: usize = 0;
    for (parts.items) |p| {
        @memcpy(replacement[offset..][0..p.len], p);
        offset += p.len;
    }

    if (ctx.fixes) |fixes| {
        try fixes.append(ctx.alloc, .{
            .start = sp.start,
            .end = sp.end,
            .replacement = replacement,
        });
    } else {
        ctx.alloc.free(replacement);
    }
}

fn collectTemplateParts(arena: *const Arena, node_id: NodeId, source: []const u8, parts: *std.ArrayListUnmanaged([]const u8), alloc: std.mem.Allocator) !void {
    const node = arena.get(node_id);
    if (node.* == .str_lit) {
        const raw = node.str_lit.raw;
        if (raw.len >= 2) {
            const inner = raw[1 .. raw.len - 1];
            try parts.append(alloc, inner);
        }
    } else if (node.* == .binary_expr and node.binary_expr.op == .plus) {
        try collectTemplateParts(arena, node.binary_expr.left, source, parts, alloc);
        try collectTemplateParts(arena, node.binary_expr.right, source, parts, alloc);
    } else {
        const sp = node.span();
        const expr = source[sp.start..sp.end];
        const prefix = "${";
        const suffix = "}";
        const wrapped = try alloc.alloc(u8, prefix.len + expr.len + suffix.len);
        @memcpy(wrapped[0..prefix.len], prefix);
        @memcpy(wrapped[prefix.len..][0..expr.len], expr);
        @memcpy(wrapped[prefix.len + expr.len ..], suffix);
        try parts.append(alloc, wrapped);
    }
}

fn runNoConstructorReturn(arena: *const Arena, _: NodeId, node: *const Node, ctx: common.LintContext, rule: common.LintRule) !void {
    if (node.* != .class_decl) return;
    for (node.class_decl.body) |m| {
        if (m.kind == .constructor) {
            if (m.value) |body_id| {
                const body = arena.get(body_id);
                if (body.* == .block) {
                    for (body.block.body) |stmt_id| {
                        const stmt = arena.get(stmt_id);
                        if (stmt.* == .return_stmt and stmt.return_stmt.argument != null) {
                            try reportNode(ctx, rule, "unexpected return value in constructor", stmt);
                        }
                    }
                }
            }
        }
    }
}

pub fn registerAll(registry: anytype, alloc: std.mem.Allocator) !void {
    const rules = [_]common.LintRule{
        .{ .code = "no-debugger", .severity = .err, .run = struct {
            fn call(ctx: common.LintContext, rule: common.LintRule) anyerror!void {
                try scanNodes(ctx, rule, runNoDebugger);
            }
        }.call },
        .{ .code = "no-alert", .severity = .err, .run = struct {
            fn call(ctx: common.LintContext, rule: common.LintRule) anyerror!void {
                try scanNodes(ctx, rule, runNoAlert);
            }
        }.call },
        .{ .code = "no-eval", .severity = .err, .run = struct {
            fn call(ctx: common.LintContext, rule: common.LintRule) anyerror!void {
                try scanNodes(ctx, rule, runNoEval);
            }
        }.call },
        .{ .code = "no-empty", .severity = .err, .run = struct {
            fn call(ctx: common.LintContext, rule: common.LintRule) anyerror!void {
                try scanNodes(ctx, rule, runNoEmpty);
            }
        }.call },
        .{ .code = "no-compare-neg-zero", .severity = .err, .run = struct {
            fn call(ctx: common.LintContext, rule: common.LintRule) anyerror!void {
                try scanNodes(ctx, rule, runNoCompareNegZero);
            }
        }.call },
        .{ .code = "no-cond-assign", .severity = .err, .run = struct {
            fn call(ctx: common.LintContext, rule: common.LintRule) anyerror!void {
                try scanNodes(ctx, rule, runNoCondAssign);
            }
        }.call },
        .{ .code = "no-constant-condition", .severity = .err, .run = struct {
            fn call(ctx: common.LintContext, rule: common.LintRule) anyerror!void {
                try scanNodes(ctx, rule, runNoConstantCondition);
            }
        }.call },
        .{ .code = "no-control-regex", .severity = .err, .run = struct {
            fn call(ctx: common.LintContext, rule: common.LintRule) anyerror!void {
                try scanNodes(ctx, rule, runNoControlRegex);
            }
        }.call },
        .{ .code = "no-delete-var", .severity = .err, .run = struct {
            fn call(ctx: common.LintContext, rule: common.LintRule) anyerror!void {
                try scanNodes(ctx, rule, runNoDeleteVar);
            }
        }.call },
        .{ .code = "no-dupe-keys", .severity = .err, .run = struct {
            fn call(ctx: common.LintContext, rule: common.LintRule) anyerror!void {
                try scanNodes(ctx, rule, runNoDupeKeys);
            }
        }.call },
        .{ .code = "no-duplicate-case", .severity = .err, .run = struct {
            fn call(ctx: common.LintContext, rule: common.LintRule) anyerror!void {
                try scanNodes(ctx, rule, runNoDuplicateCase);
            }
        }.call },
        .{ .code = "no-empty-pattern", .severity = .err, .run = struct {
            fn call(ctx: common.LintContext, rule: common.LintRule) anyerror!void {
                try scanNodes(ctx, rule, runNoEmptyPattern);
            }
        }.call },
        .{ .code = "no-ex-assign", .severity = .err, .run = struct {
            fn call(ctx: common.LintContext, rule: common.LintRule) anyerror!void {
                try scanNodes(ctx, rule, runNoExAssign);
            }
        }.call },
        .{ .code = "no-extra-boolean-cast", .severity = .err, .run = struct {
            fn call(ctx: common.LintContext, rule: common.LintRule) anyerror!void {
                try scanNodes(ctx, rule, runNoExtraBooleanCast);
            }
        }.call },
        .{ .code = "no-func-assign", .severity = .err, .run = struct {
            fn call(ctx: common.LintContext, rule: common.LintRule) anyerror!void {
                try scanNodes(ctx, rule, runNoFuncAssign);
            }
        }.call },
        .{ .code = "no-global-assign", .severity = .err, .run = struct {
            fn call(ctx: common.LintContext, rule: common.LintRule) anyerror!void {
                try scanNodes(ctx, rule, runNoGlobals);
            }
        }.call },
        .{ .code = "no-new-native-nonconstructor", .severity = .err, .run = struct {
            fn call(ctx: common.LintContext, rule: common.LintRule) anyerror!void {
                try scanNodes(ctx, rule, runNoNewNativeNonconstructor);
            }
        }.call },
        .{ .code = "no-nonoctal-decimal-escape", .severity = .err, .run = struct {
            fn call(ctx: common.LintContext, rule: common.LintRule) anyerror!void {
                try scanNodes(ctx, rule, runNoNonoctalDecimalEscape);
            }
        }.call },
        .{ .code = "no-obj-calls", .severity = .err, .run = struct {
            fn call(ctx: common.LintContext, rule: common.LintRule) anyerror!void {
                try scanNodes(ctx, rule, runNoObjCalls);
            }
        }.call },
        .{ .code = "no-octal", .severity = .err, .run = struct {
            fn call(ctx: common.LintContext, rule: common.LintRule) anyerror!void {
                try scanNodes(ctx, rule, runNoOctal);
            }
        }.call },
        .{ .code = "no-prototype-builtins", .severity = .err, .run = struct {
            fn call(ctx: common.LintContext, rule: common.LintRule) anyerror!void {
                try scanNodes(ctx, rule, runNoPrototypeBuiltins);
            }
        }.call },
        .{ .code = "no-self-assign", .severity = .err, .run = struct {
            fn call(ctx: common.LintContext, rule: common.LintRule) anyerror!void {
                try scanNodes(ctx, rule, runNoSelfAssign);
            }
        }.call },
        .{ .code = "no-sparse-arrays", .severity = .err, .run = struct {
            fn call(ctx: common.LintContext, rule: common.LintRule) anyerror!void {
                try scanNodes(ctx, rule, runNoSparseArrays);
            }
        }.call },
        .{ .code = "no-unsafe-negation", .severity = .err, .run = struct {
            fn call(ctx: common.LintContext, rule: common.LintRule) anyerror!void {
                try scanNodes(ctx, rule, runNoUnsafeNegation);
            }
        }.call },
        .{ .code = "no-unsafe-optional-chaining", .severity = .err, .run = struct {
            fn call(ctx: common.LintContext, rule: common.LintRule) anyerror!void {
                try scanNodes(ctx, rule, runNoUnsafeOptionalChaining);
            }
        }.call },
        .{ .code = "no-useless-catch", .severity = .err, .run = struct {
            fn call(ctx: common.LintContext, rule: common.LintRule) anyerror!void {
                try scanNodes(ctx, rule, runNoUselessCatch);
            }
        }.call },
        .{ .code = "for-direction", .severity = .err, .run = struct {
            fn call(ctx: common.LintContext, rule: common.LintRule) anyerror!void {
                try scanNodes(ctx, rule, runForDirection);
            }
        }.call },
        .{ .code = "use-isnan", .severity = .err, .run = struct {
            fn call(ctx: common.LintContext, rule: common.LintRule) anyerror!void {
                try scanNodes(ctx, rule, runUseIsNaN);
            }
        }.call },
        .{ .code = "valid-typeof", .severity = .err, .run = struct {
            fn call(ctx: common.LintContext, rule: common.LintRule) anyerror!void {
                try scanNodes(ctx, rule, runValidTypeof);
            }
        }.call },
        .{ .code = "no-const-assign", .severity = .err, .run = struct {
            fn call(ctx: common.LintContext, rule: common.LintRule) anyerror!void {
                try scanNodes(ctx, rule, runNoConstAssign);
            }
        }.call },
        .{ .code = "no-class-assign", .severity = .err, .run = struct {
            fn call(ctx: common.LintContext, rule: common.LintRule) anyerror!void {
                try scanNodes(ctx, rule, runNoClassAssign);
            }
        }.call },
        .{ .code = "no-dupe-args", .severity = .err, .run = struct {
            fn call(ctx: common.LintContext, rule: common.LintRule) anyerror!void {
                try scanNodes(ctx, rule, runNoDupeArgs);
            }
        }.call },
        .{ .code = "no-dupe-class-members", .severity = .err, .run = struct {
            fn call(ctx: common.LintContext, rule: common.LintRule) anyerror!void {
                try scanNodes(ctx, rule, runNoDupeClassMembers);
            }
        }.call },
        .{ .code = "no-dupe-else-if", .severity = .err, .run = struct {
            fn call(ctx: common.LintContext, rule: common.LintRule) anyerror!void {
                try scanNodes(ctx, rule, runNoDupeElseIf);
            }
        }.call },
        .{ .code = "no-case-declarations", .severity = .err, .run = struct {
            fn call(ctx: common.LintContext, rule: common.LintRule) anyerror!void {
                try scanNodes(ctx, rule, runNoCaseDeclarations);
            }
        }.call },
        .{ .code = "no-async-promise-executor", .severity = .err, .run = struct {
            fn call(ctx: common.LintContext, rule: common.LintRule) anyerror!void {
                try scanNodes(ctx, rule, runNoAsyncPromiseExecutor);
            }
        }.call },
        .{ .code = "no-constant-binary-expression", .severity = .err, .run = struct {
            fn call(ctx: common.LintContext, rule: common.LintRule) anyerror!void {
                try scanNodes(ctx, rule, runNoConstantBinaryExpression);
            }
        }.call },
        .{ .code = "no-import-assign", .severity = .err, .run = struct {
            fn call(ctx: common.LintContext, rule: common.LintRule) anyerror!void {
                try scanNodes(ctx, rule, runNoImportAssign);
            }
        }.call },
        .{ .code = "no-shadow-restricted-names", .severity = .err, .run = struct {
            fn call(ctx: common.LintContext, rule: common.LintRule) anyerror!void {
                try scanNodes(ctx, rule, runNoShadowRestrictedNames);
            }
        }.call },
        .{ .code = "no-unreachable", .severity = .err, .run = struct {
            fn call(ctx: common.LintContext, rule: common.LintRule) anyerror!void {
                try scanNodes(ctx, rule, runNoUnreachable);
            }
        }.call },
        .{ .code = "no-unsafe-finally", .severity = .err, .run = struct {
            fn call(ctx: common.LintContext, rule: common.LintRule) anyerror!void {
                try scanNodes(ctx, rule, runNoUnsafeFinally);
            }
        }.call },
        .{ .code = "no-unused-vars", .severity = .err, .run = struct {
            fn call(ctx: common.LintContext, rule: common.LintRule) anyerror!void {
                try scanNodes(ctx, rule, runNoUnusedVars);
            }
        }.call },
        .{ .code = "no-undef", .severity = .err, .run = struct {
            fn call(ctx: common.LintContext, rule: common.LintRule) anyerror!void {
                try scanNodes(ctx, rule, runNoUndef);
            }
        }.call },
        .{ .code = "require-yield", .severity = .err, .run = struct {
            fn call(ctx: common.LintContext, rule: common.LintRule) anyerror!void {
                try scanNodes(ctx, rule, runRequireYield);
            }
        }.call },
        .{ .code = "no-fallthrough", .severity = .err, .run = struct {
            fn call(ctx: common.LintContext, rule: common.LintRule) anyerror!void {
                try scanNodes(ctx, rule, runNoFallthrough);
            }
        }.call },
        .{ .code = "no-empty-static-block", .severity = .err, .run = struct {
            fn call(ctx: common.LintContext, rule: common.LintRule) anyerror!void {
                try scanNodes(ctx, rule, runNoEmptyStaticBlock);
            }
        }.call },
        .{ .code = "no-self-compare", .severity = .err, .run = struct {
            fn call(ctx: common.LintContext, rule: common.LintRule) anyerror!void {
                try scanNodes(ctx, rule, runNoSelfCompare);
            }
        }.call },
        .{ .code = "no-template-curly-in-string", .severity = .err, .run = struct {
            fn call(ctx: common.LintContext, rule: common.LintRule) anyerror!void {
                try scanNodes(ctx, rule, runNoTemplateCurlyInString);
            }
        }.call },
        .{ .code = "no-await-in-loop", .severity = .err, .run = struct {
            fn call(ctx: common.LintContext, rule: common.LintRule) anyerror!void {
                try scanNodes(ctx, rule, runNoAwaitInLoop);
            }
        }.call },
        .{ .code = "no-promise-executor-return", .severity = .err, .run = struct {
            fn call(ctx: common.LintContext, rule: common.LintRule) anyerror!void {
                try scanNodes(ctx, rule, runNoPromiseExecutorReturn);
            }
        }.call },
        .{ .code = "no-inner-declarations", .severity = .err, .run = struct {
            fn call(ctx: common.LintContext, rule: common.LintRule) anyerror!void {
                try scanNodes(ctx, rule, runNoInnerDeclarations);
            }
        }.call },
        .{ .code = "preserve-caught-error", .severity = .err, .run = struct {
            fn call(ctx: common.LintContext, rule: common.LintRule) anyerror!void {
                try scanNodes(ctx, rule, runPreserveCaughtError);
            }
        }.call },
        .{ .code = "no-var", .severity = .err, .run = struct {
            fn call(ctx: common.LintContext, rule: common.LintRule) anyerror!void {
                try scanNodes(ctx, rule, runNoVar);
            }
        }.call },
        .{ .code = "prefer-template", .severity = .warn, .run = struct {
            fn call(ctx: common.LintContext, rule: common.LintRule) anyerror!void {
                try scanNodes(ctx, rule, runPreferTemplate);
            }
        }.call, .fix = struct {
            fn call(ctx: common.LintContext, rule: common.LintRule) anyerror!void {
                try scanNodes(ctx, rule, fixPreferTemplate);
            }
        }.call },
        .{ .code = "no-constructor-return", .severity = .err, .run = struct {
            fn call(ctx: common.LintContext, rule: common.LintRule) anyerror!void {
                try scanNodes(ctx, rule, runNoConstructorReturn);
            }
        }.call },
    };
    for (rules) |rule| {
        try registry.register(alloc, rule);
    }
}
