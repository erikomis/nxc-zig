const std = @import("std");
const ast = @import("ast");

const NodeId = ast.NodeId;

pub const DeclarationGenOptions = struct {
    source: []const u8,
};

pub const DeclarationGen = struct {
    arena: *const ast.Arena,
    alloc: std.mem.Allocator,
    buf: std.ArrayListUnmanaged(u8) = .empty,
    indent_level: u32 = 0,
    opts: DeclarationGenOptions,

    pub fn init(arena: *const ast.Arena, alloc: std.mem.Allocator, opts: DeclarationGenOptions) DeclarationGen {
        return .{ .arena = arena, .alloc = alloc, .opts = opts };
    }

    pub fn finish(self: *DeclarationGen) ![]const u8 {
        return self.buf.toOwnedSlice(self.alloc);
    }

    fn w(self: *DeclarationGen, s: []const u8) !void {
        try self.buf.appendSlice(self.alloc, s);
    }

    fn wb(self: *DeclarationGen, b: u8) !void {
        try self.buf.append(self.alloc, b);
    }

    fn nl(self: *DeclarationGen) !void {
        try self.wb('\n');
        var i: u32 = 0;
        while (i < self.indent_level * 2) : (i += 1) try self.wb(' ');
    }

    fn sourceSlice(self: *DeclarationGen, span: ast.Span) []const u8 {
        const start: usize = @min(@as(usize, @intCast(span.start)), self.opts.source.len);
        const end: usize = @min(@as(usize, @intCast(span.end)), self.opts.source.len);
        if (end <= start) return "any";
        return std.mem.trim(u8, self.opts.source[start..end], " \t\r\n");
    }

    pub fn gen(self: *DeclarationGen, program_id: NodeId) !void {
        const program = self.arena.get(program_id).program;
        var first = true;
        const is_module = self.hasTopLevelModuleSyntax(program.body);

        for (program.body) |stmt_id| {
            var tmp = DeclarationGen.init(self.arena, self.alloc, self.opts);
            defer tmp.buf.deinit(self.alloc);

            try tmp.genTopLevel(stmt_id, false, is_module);

            if (tmp.buf.items.len == 0) {
                continue;
            }

            if (!first) {
                try self.nl();
            }

            try self.w(tmp.buf.items);
            first = false;
        }
    }

    fn hasTopLevelModuleSyntax(self: *DeclarationGen, body: []const NodeId) bool {
        for (body) |stmt_id| {
            switch (self.arena.get(stmt_id).*) {
                .import_decl, .export_decl => return true,
                else => {},
            }
        }
        return false;
    }

    fn genTopLevel(self: *DeclarationGen, stmt_id: NodeId, already_exported: bool, is_module: bool) anyerror!void {
        switch (self.arena.get(stmt_id).*) {
            .export_decl => |exp| try self.genExport(exp, is_module),
            .import_decl => |imp| try self.genImportForDts(imp),
            .ts_interface => |i| {
                if (already_exported) {
                    try self.w("export ");
                }
                try self.genInterface(i);
            },
            .ts_type_alias => |t| {
                if (already_exported) {
                    try self.w("export ");
                }
                try self.genTypeAlias(t);
            },
            .ts_enum => |e| {
                if (already_exported) {
                    try self.w("export declare ");
                } else {
                    try self.w("declare ");
                }
                try self.genEnum(e);
            },
            .ts_namespace => |n| {
                if (already_exported) {
                    try self.w("export declare ");
                } else {
                    try self.w("declare ");
                }
                try self.genNamespace(n);
            },
            .fn_decl => |f| if (f.id) |_| {
                if (already_exported) {
                    try self.w("export declare ");
                } else {
                    try self.w("declare ");
                }
                try self.genFunctionDecl(f);
            },
            .class_decl => |c| if (c.id) |_| {
                if (already_exported) {
                    try self.w("export ");
                }
                try self.genClassDecl(c);
            },
            .var_decl => |v| {
                if (already_exported) {
                    try self.w("export declare ");
                } else {
                    try self.w("declare ");
                }
                try self.genVarDecl(v);
            },
            else => {},
        }
    }

    fn genExport(self: *DeclarationGen, exp: ast.ExportDecl, is_module: bool) anyerror!void {
        switch (exp.kind) {
            .decl => |decl_id| {
                try self.genTopLevel(decl_id, true, is_module);
            },
            .default_decl => |decl_id| {
                try self.w("export default ");
                switch (self.arena.get(decl_id).*) {
                    .fn_decl => |f| try self.genFunctionDecl(f),
                    .class_decl => |c| try self.genClassDecl(c),
                    else => try self.w("any;"),
                }
            },
            .default_expr => try self.w("export default any;"),
            .named => |n| {
                try self.w("export { ");
                for (n.specifiers, 0..) |s, i| {
                    if (i > 0) try self.w(", ");
                    try self.genName(s.local);
                    const local_name = self.arena.get(s.local).ident.name;
                    const exported_name = self.arena.get(s.exported).ident.name;
                    if (!std.mem.eql(u8, local_name, exported_name)) {
                        try self.w(" as ");
                        try self.genName(s.exported);
                    }
                }
                try self.w(" }");
                if (n.source) |src| {
                    try self.w(" from ");
                    try self.genName(src);
                }
                try self.w(";");
            },
            .all => |a| {
                try self.w("export *");
                if (a.exported) |e| {
                    try self.w(" as ");
                    try self.genName(e);
                }
                try self.w(" from ");
                try self.genName(a.source);
                try self.w(";");
            },
        }
    }

    fn genImportForDts(self: *DeclarationGen, imp: ast.ImportDecl) !void {
        // Keep type-only imports in declarations; value imports are implementation-only.
        if (!imp.is_type_only) {
            var has_type_spec = false;
            for (imp.specifiers) |s| {
                if (s.is_type_only) {
                    has_type_spec = true;
                }
            }
            if (!has_type_spec) return;
        }

        try self.w("import ");
        if (imp.is_type_only) try self.w("type ");
        if (imp.specifiers.len == 0) {
            try self.genName(imp.source);
            try self.w(";");
            return;
        }
        try self.w("{ ");
        var emitted: usize = 0;
        for (imp.specifiers) |s| {
            if (!imp.is_type_only and !s.is_type_only) continue;
            if (emitted > 0) try self.w(", ");
            if (!imp.is_type_only) try self.w("type ");
            if (s.imported) |imported| {
                try self.genName(imported);
                const local_name = self.arena.get(s.local).ident.name;
                const imported_name = self.arena.get(imported).ident.name;
                if (!std.mem.eql(u8, local_name, imported_name)) {
                    try self.w(" as ");
                    try self.genName(s.local);
                }
            } else try self.genName(s.local);
            emitted += 1;
        }
        try self.w(" } from ");
        try self.genName(imp.source);
        try self.w(";");
    }

    fn genInterface(self: *DeclarationGen, i: ast.TsInterfaceDecl) !void {
        try self.w("interface ");
        try self.genName(i.id);
        try self.genTypeParams(i.type_params);
        if (i.extends.len > 0) {
            try self.w(" extends ");
            for (i.extends, 0..) |ext, idx| {
                if (idx > 0) try self.w(", ");
                try self.genType(ext);
            }
        }
        try self.w(" {}");
    }

    fn genTypeAlias(self: *DeclarationGen, t: ast.TsTypeAliasDecl) !void {
        try self.w("type ");
        try self.genName(t.id);
        try self.genTypeParams(t.type_params);
        try self.w(" = ");
        try self.genType(t.type_ann);
        try self.w(";");
    }

    fn genEnum(self: *DeclarationGen, e: ast.TsEnumDecl) !void {
        if (e.is_const) try self.w("const ");
        try self.w("enum ");
        try self.genName(e.id);
        try self.w(" {");
        self.indent_level += 1;
        for (e.members, 0..) |m, i| {
            try self.nl();
            try self.genName(m.id);
            if (m.init) |member_init| {
                try self.w(" = ");
                try self.genExprAsText(member_init);
            }
            if (i + 1 < e.members.len) try self.w(",");
        }
        self.indent_level -= 1;
        if (e.members.len > 0) try self.nl();
        try self.w("}");
    }

    fn genNamespace(self: *DeclarationGen, n: ast.TsNamespaceDecl) !void {
        try self.w("namespace ");
        try self.genName(n.id);
        try self.w(" {");
        self.indent_level += 1;
        for (n.body) |stmt| {
            const before = self.buf.items.len;
            try self.nl();
            try self.genTopLevel(stmt, false, false);
            if (self.buf.items.len == before + 1) self.buf.items.len = before;
        }
        self.indent_level -= 1;
        try self.nl();
        try self.w("}");
    }

    fn genFunctionDecl(self: *DeclarationGen, f: ast.FnDecl) !void {
        if (f.is_async) try self.w("async ");
        try self.w("function");
        if (f.is_generator) try self.wb('*');
        if (f.id) |id| {
            try self.wb(' ');
            try self.genName(id);
        }
        try self.genTypeParams(f.type_params);
        try self.genParams(f.params, f.param_types);
        try self.w(": ");
        if (f.return_type) |ret| try self.genType(ret) else try self.w("any");
        try self.w(";");
    }

    fn genClassDecl(self: *DeclarationGen, c: ast.ClassDecl) !void {
        try self.w("declare class ");
        try self.genName(c.id.?);
        try self.genTypeParams(c.type_params);
        if (c.super_class) |sc| {
            try self.w(" extends ");
            try self.genExprAsText(sc);
        }
        try self.w(" {");
        self.indent_level += 1;
        for (c.body) |m| {
            try self.nl();
            try self.genClassMember(m);
        }
        self.indent_level -= 1;
        if (c.body.len > 0) try self.nl();
        try self.w("}");
    }

    fn genClassMember(self: *DeclarationGen, m: ast.ClassMember) !void {
        if (m.accessibility) |a| try self.w(switch (a) {
            .public => "public ",
            .private => "private ",
            .protected => "protected ",
        });
        if (m.is_static) try self.w("static ");
        if (m.is_readonly) try self.w("readonly ");
        switch (m.kind) {
            .constructor => {
                try self.w("constructor");
                if (m.value) |v| {
                    const f = self.arena.get(v).fn_expr;
                    try self.genParams(f.params, f.param_types);
                } else try self.w("()");
                try self.w(";");
            },
            .method, .getter, .setter => {
                if (m.kind == .getter) try self.w("get ");
                if (m.kind == .setter) try self.w("set ");
                try self.genName(m.key);
                if (m.value) |v| {
                    const f = self.arena.get(v).fn_expr;
                    try self.genTypeParams(f.type_params);
                    try self.genParams(f.params, f.param_types);
                    try self.w(": ");
                    if (f.return_type) |ret| try self.genType(ret) else try self.w("any");
                } else try self.w("(): any");
                try self.w(";");
            },
            .field, .auto_accessor => {
                if (m.kind == .auto_accessor) try self.w("accessor ");
                try self.genName(m.key);
                if (m.is_optional) try self.w("?");
                try self.w(": ");
                if (m.type_ann) |typ| try self.genType(typ) else try self.w("any");
                try self.w(";");
            },
            .static_block => try self.w("// static block omitted"),
        }
    }

    fn genVarDecl(self: *DeclarationGen, v: ast.VarDecl) !void {
        try self.w(switch (v.kind) {
            .@"const" => "const ",
            .@"var" => "var ",
            .let => "let ",
            .using => "let ",
        });
        for (v.declarators, 0..) |d, i| {
            if (i > 0) try self.w(", ");
            try self.genName(d.id);

            if (d.type_ann) |typ| {
                try self.w(": ");
                try self.genType(typ);
            } else if (v.kind == .@"const" and d.init != null and try self.genConstLiteralInitializer(d.init.?)) {
                // TypeScript emits literal initializers for const declarations in .d.ts.
            } else {
                try self.w(": ");
                if (d.init) |init_id| {
                    try self.genInferredTypeFromInitializer(init_id);
                } else {
                    try self.w("any");
                }
            }
        }
        try self.w(";");
    }

    fn genParams(self: *DeclarationGen, params: []const NodeId, param_types: []const ?NodeId) !void {
        try self.w("(");
        for (params, 0..) |p, i| {
            if (i > 0) try self.w(", ");
            try self.genParamName(p);
            try self.w(": ");
            if (i < param_types.len and param_types[i] != null) try self.genType(param_types[i].?) else try self.w("any");
        }
        try self.w(")");
    }

    fn genConstLiteralInitializer(self: *DeclarationGen, id: NodeId) !bool {
        switch (self.arena.get(id).*) {
            .str_lit => |s| {
                try self.w(" = ");
                try self.writeStringLiteralValue(s.value);
                return true;
            },
            .num_lit => |n| {
                try self.w(" = ");
                try self.w(n.raw);
                return true;
            },
            .bool_lit => |b| {
                try self.w(" = ");
                try self.w(if (b.value) "true" else "false");
                return true;
            },
            else => return false,
        }
    }

    fn genInferredTypeFromInitializer(self: *DeclarationGen, id: NodeId) !void {
        switch (self.arena.get(id).*) {
            .str_lit => try self.w("string"),
            .num_lit => try self.w("number"),
            .bool_lit => try self.w("boolean"),
            .null_lit => try self.w("null"),
            .undefined_ref => try self.w("undefined"),
            else => try self.w("any"),
        }
    }

    fn writeStringLiteralValue(self: *DeclarationGen, value: []const u8) !void {
        try self.wb('"');
        for (value) |c| {
            switch (c) {
                '\\' => try self.w("\\\\"),
                '"' => try self.w("\\\""),
                '\n' => try self.w("\\n"),
                '\r' => try self.w("\\r"),
                '\t' => try self.w("\\t"),
                else => try self.wb(c),
            }
        }
        try self.wb('"');
    }

    fn genParamName(self: *DeclarationGen, id: NodeId) !void {
        switch (self.arena.get(id).*) {
            .rest_elem => |r| {
                try self.w("...");
                try self.genParamName(r.argument);
            },
            .assign_pat => |a| try self.genParamName(a.left),
            .ident => |ident| try self.w(ident.name),
            else => try self.w("arg"),
        }
    }

    fn genTypeParams(self: *DeclarationGen, params: []const ast.TsTypeParam) !void {
        if (params.len == 0) return;
        try self.w("<");
        for (params, 0..) |p, i| {
            if (i > 0) try self.w(", ");
            try self.genName(p.name);
            if (p.constraint) |c| {
                try self.w(" extends ");
                try self.genType(c);
            }
            if (p.default_type) |d| {
                try self.w(" = ");
                try self.genType(d);
            }
        }
        try self.w(">");
    }

    fn genType(self: *DeclarationGen, id: NodeId) !void {
        switch (self.arena.get(id).*) {
            .ts_keyword => |k| try self.w(switch (k.keyword) {
                .any => "any",
                .unknown => "unknown",
                .never => "never",
                .void_kw => "void",
                .undefined_kw => "undefined",
                .null_kw => "null",
                .boolean => "boolean",
                .number => "number",
                .string => "string",
                .bigint => "bigint",
                .symbol => "symbol",
                .object => "object",
            }),
            .ts_type_ref => |r| {
                try self.genType(r.name);
                if (r.type_args.len > 0) {
                    try self.w("<");
                    for (r.type_args, 0..) |arg, i| {
                        if (i > 0) try self.w(", ");
                        try self.genType(arg);
                    }
                    try self.w(">");
                }
            },
            .ts_qualified_name => |q| {
                try self.genType(q.left);
                try self.w(".");
                try self.genType(q.right);
            },
            .ts_union => |u| for (u.types, 0..) |t, i| {
                if (i > 0) try self.w(" | ");
                try self.genType(t);
            },
            .ts_intersection => |it| for (it.types, 0..) |t, i| {
                if (i > 0) try self.w(" & ");
                try self.genType(t);
            },
            .ts_array_type => |a| {
                try self.genType(a.elem);
                try self.w("[]");
            },
            .ts_tuple => |tup| {
                try self.w("[");
                for (tup.types, 0..) |t, i| {
                    if (i > 0) try self.w(", ");
                    try self.genType(t);
                }
                try self.w("]");
            },
            .ident, .str_lit => try self.genName(id),
            else => try self.w(self.sourceSlice(self.arena.get(id).span())),
        }
    }

    fn genExprAsText(self: *DeclarationGen, id: NodeId) !void {
        try self.w(self.sourceSlice(self.arena.get(id).span()));
    }

    fn genName(self: *DeclarationGen, id: NodeId) !void {
        switch (self.arena.get(id).*) {
            .ident => |i| try self.w(i.name),
            .str_lit => |s| try self.w(s.raw),
            else => try self.w(self.sourceSlice(self.arena.get(id).span())),
        }
    }
};

pub fn generate(arena: *const ast.Arena, alloc: std.mem.Allocator, source: []const u8, program_id: NodeId) ![]const u8 {
    var genr = DeclarationGen.init(arena, alloc, .{ .source = source });
    try genr.gen(program_id);
    return genr.finish();
}
