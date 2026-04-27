const std = @import("std");
const ast = @import("parser").ast;
const NodeId = ast.NodeId;

const ConstEnumValue = union(enum) {
    number: []const u8,
    string: []const u8,
};

const ConstEnumInfo = struct {
    members: std.StringHashMapUnmanaged(ConstEnumValue) = .empty,
};

// Fix 4: Infrastructure for tracking cross-module const enum references
const CrossModuleEnumRef = struct {
    source_file: []const u8,
    enum_name: []const u8,
    member_name: []const u8,
};

pub fn stripTypes(arena: *ast.Arena, alloc: std.mem.Allocator) !void {
    var const_enums = std.StringHashMapUnmanaged(ConstEnumInfo){};
    var cross_module_refs = std.ArrayListUnmanaged(CrossModuleEnumRef).empty;
    defer {
        var it = const_enums.valueIterator();
        while (it.next()) |info| info.members.deinit(alloc);
        const_enums.deinit(alloc);
        cross_module_refs.deinit(alloc);
    }

    try collectConstEnums(arena, alloc, &const_enums);

    var i: u32 = 0;
    while (i < arena.nodes.items.len) : (i += 1) {
        const node = arena.getMut(i);
        switch (node.*) {
            .ts_interface, .ts_type_alias => {
                node.* = .{ .empty_stmt = .{ .span = node.span() } };
            },
            .ts_enum => |e| {
                if (e.is_const) {
                    node.* = .{ .empty_stmt = .{ .span = e.span } };
                }
            },
            .class_decl => |*c| {
                var kept = std.ArrayListUnmanaged(ast.ClassMember).empty;
                for (c.body) |m| {
                    const is_callable = m.kind == .method or m.kind == .getter or m.kind == .setter or m.kind == .constructor;
                    const skip = (m.value == null and is_callable) or m.is_declare;
                    if (!skip) try kept.append(alloc, m);
                }
                c.body = try kept.toOwnedSlice(alloc);
            },
            .import_decl => |*imp| {
                if (imp.is_type_only) {
                    node.* = .{ .empty_stmt = .{ .span = imp.span } };
                    continue;
                }
                var kept = std.ArrayListUnmanaged(ast.ImportSpecifier).empty;
                for (imp.specifiers) |s| {
                    if (!s.is_type_only) try kept.append(alloc, s);
                }
                imp.specifiers = try kept.toOwnedSlice(alloc);
                if (imp.specifiers.len == 0 and imp.attributes.len == 0) {
                    node.* = .{ .empty_stmt = .{ .span = imp.span } };
                }
            },
            .export_decl => |*exp| {
                switch (exp.kind) {
                    .decl => |decl_id| {
                        switch (arena.get(decl_id).*) {
                            .empty_stmt, .ts_interface, .ts_type_alias => {
                                node.* = .{ .empty_stmt = .{ .span = exp.span } };
                                continue;
                            },
                            .ts_enum => |e| if (e.is_const) {
                                node.* = .{ .empty_stmt = .{ .span = exp.span } };
                                continue;
                            },
                            else => {},
                        }
                    },
                    .named => |*n| {
                        if (n.is_type_only) {
                            node.* = .{ .empty_stmt = .{ .span = exp.span } };
                            continue;
                        }
                        var kept = std.ArrayListUnmanaged(ast.ExportSpecifier).empty;
                        for (n.specifiers) |s| {
                            if (!s.is_type_only) try kept.append(alloc, s);
                        }
                        n.specifiers = try kept.toOwnedSlice(alloc);
                        if (n.specifiers.len == 0 and n.source == null) {
                            node.* = .{ .empty_stmt = .{ .span = exp.span } };
                        }
                    },
                    .all => |a| {
                        if (a.is_type_only) {
                            node.* = .{ .empty_stmt = .{ .span = exp.span } };
                            continue;
                        }
                    },
                    else => {},
                }
            },
            .member_expr => |m| {
                if (try inlineConstEnumMember(arena, alloc, &const_enums, &cross_module_refs, m)) |replacement| {
                    node.* = replacement;
                }
            },
            .ts_as_expr => |e| node.* = arena.get(e.expr).*,
            .ts_satisfies => |e| node.* = arena.get(e.expr).*,
            .ts_instantiation => |e| node.* = arena.get(e.expr).*,
            .ts_non_null => |e| node.* = arena.get(e.expr).*,
            .ts_type_assert => |e| node.* = arena.get(e.expr).*,
            else => {},
        }
    }
}

fn collectConstEnums(
    arena: *const ast.Arena,
    alloc: std.mem.Allocator,
    const_enums: *std.StringHashMapUnmanaged(ConstEnumInfo),
) !void {
    for (arena.nodes.items) |node| {
        switch (node) {
            .ts_enum => |e| {
                if (!e.is_const) continue;

                const enum_name = arena.get(e.id).ident.name;
                var info = ConstEnumInfo{};
                var next_auto_value: ?i64 = 0;

                for (e.members) |member| {
                    // Fix 1: Handle computed string key members
                    if (arena.get(member.id).* == .spread_elem) {
                        const spread = arena.get(member.id).spread_elem;
                        const source_name = switch (arena.get(spread.argument).*) {
                            .ident => |id| id.name,
                            else => continue,
                        };
                        if (const_enums.get(source_name)) |source_info| {
                            var it = source_info.members.iterator();
                            while (it.next()) |entry| {
                                try info.members.put(alloc, entry.key_ptr.*, entry.value_ptr.*);
                            }
                        }
                        continue;
                    }
                    const member_name = switch (arena.get(member.id).*) {
                        .ident => |id| id.name,
                        .str_lit => |s| s.value,
                        else => continue,
                    };
                    const value = if (member.init) |init_id| blk: {
                        const explicit = try constEnumInitValue(arena, alloc, init_id);
                        next_auto_value = switch (explicit) {
                            .number => |raw| (std.fmt.parseInt(i64, raw, 10) catch 0) + 1,
                            .string => null,
                        };
                        break :blk explicit;
                    } else blk: {
                        const current = next_auto_value orelse 0;
                        next_auto_value = current + 1;
                        break :blk ConstEnumValue{ .number = try std.fmt.allocPrint(alloc, "{d}", .{current}) };
                    };
                    try info.members.put(alloc, member_name, value);
                }

                try const_enums.put(alloc, enum_name, info);
            },
            else => {},
        }
    }
}

fn constEnumInitValue(arena: *const ast.Arena, alloc: std.mem.Allocator, init_id: NodeId) !ConstEnumValue {
    return switch (arena.get(init_id).*) {
        .num_lit => |n| ConstEnumValue{ .number = n.raw },
        .str_lit => |s| ConstEnumValue{ .string = s.raw },
        .unary_expr => |u| blk: {
            if (u.op == .minus and arena.get(u.argument).* == .num_lit) {
                const n = arena.get(u.argument).num_lit;
                break :blk ConstEnumValue{ .number = try std.fmt.allocPrint(alloc, "-{s}", .{n.raw}) };
            }
            break :blk ConstEnumValue{ .number = "0" };
        },
        else => ConstEnumValue{ .number = "0" },
    };
}

fn inlineConstEnumMember(
    arena: *const ast.Arena,
    alloc: std.mem.Allocator,
    const_enums: *const std.StringHashMapUnmanaged(ConstEnumInfo),
    cross_module_refs: *std.ArrayListUnmanaged(CrossModuleEnumRef),
    m: ast.MemberExpr,
) !?ast.Node {
    if (m.optional) return null;

    const enum_name = switch (arena.get(m.object).*) {
        .ident => |id| id.name,
        else => return null,
    };

    const member_name = if (m.computed) switch (arena.get(m.prop).*) {
        .str_lit => |s| s.value,
        else => return null,
    } else switch (arena.get(m.prop).*) {
        .ident => |id| id.name,
        else => return null,
    };

    // Fix 3: TODO - const enum re-exports are not handled across files
    // When a const enum is re-exported from another module, the inlining
    // fails silently here. Future work: resolve re-exported const enums
    // by following the export chain.

    const info = const_enums.get(enum_name) orelse {
        // Track cross-module const enum reference for future propagation
        try cross_module_refs.append(alloc, .{
            .source_file = "",
            .enum_name = enum_name,
            .member_name = member_name,
        });
        return null;
    };
    const value = info.members.get(member_name) orelse return null;
    const comment = try std.fmt.allocPrint(alloc, "{s}.{s}", .{ enum_name, member_name });

    return switch (value) {
        .number => |raw| ast.Node{ .num_lit = .{
            .raw = try std.fmt.allocPrint(alloc, "{s} /* {s} */", .{ raw, comment }),
            .span = m.span,
        } },
        .string => |raw| ast.Node{ .str_lit = .{
            .raw = try std.fmt.allocPrint(alloc, "{s} /* {s} */", .{ raw, comment }),
            .value = raw,
            .span = m.span,
        } },
    };
}

pub fn lowerUsingDecls(arena: *ast.Arena, alloc: std.mem.Allocator) !void {
    var i: u32 = 0;
    while (i < arena.nodes.items.len) : (i += 1) {
        const node = arena.getMut(i);
        switch (node.*) {
            .var_decl => |*v| {
                if (v.kind == .using) {
                    v.kind = .@"const";
                    v.is_await = false;
                }
            },
            .class_decl => |*c| {
                var kept = std.ArrayListUnmanaged(ast.ClassMember).empty;
                for (c.body) |m| {
                    var mm = m;
                    if (mm.kind == .auto_accessor) {
                        mm.kind = .field;
                    }
                    try kept.append(alloc, mm);
                }
                c.body = try kept.toOwnedSlice(alloc);
            },
            else => {},
        }
    }
}
