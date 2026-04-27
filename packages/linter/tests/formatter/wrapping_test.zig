const std = @import("std");
const h = @import("harness");
const linter = @import("linter");
const common = @import("common");

test "formatter wraps long object literal at narrow printWidth" {
    const source =
        \\const data = { name: 'Luciano', age: 27, city: 'SP', country: 'Brazil' }
    ;
    const wide = try linter.format(source, .{ .singleQuote = true, .semi = false, .printWidth = 120, .tabWidth = 2 }, std.testing.allocator);
    defer std.testing.allocator.free(wide);

    try std.testing.expectEqualStrings(
        \\const data = { name: 'Luciano', age: 27, city: 'SP', country: 'Brazil' }
    , wide);

    const narrow = try linter.format(source, .{ .singleQuote = true, .semi = false, .printWidth = 30, .tabWidth = 2 }, std.testing.allocator);
    defer std.testing.allocator.free(narrow);

    try std.testing.expect(std.mem.indexOf(u8, narrow, "\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, narrow, "name: 'Luciano'") != null);
    try std.testing.expect(std.mem.indexOf(u8, narrow, "age: 27") != null);
    try std.testing.expect(std.mem.indexOf(u8, narrow, "city: 'SP'") != null);
    try std.testing.expect(std.mem.indexOf(u8, narrow, "country: 'Brazil'") != null);
}

test "formatter wraps long array literal at narrow printWidth" {
    const source = "const items = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]";

    const wide = try linter.format(source, .{ .semi = true, .printWidth = 120 }, std.testing.allocator);
    defer std.testing.allocator.free(wide);
    try std.testing.expectEqualStrings("const items = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];", wide);

    const narrow = try linter.format(source, .{ .semi = true, .printWidth = 30 }, std.testing.allocator);
    defer std.testing.allocator.free(narrow);
    try std.testing.expect(std.mem.indexOf(u8, narrow, "\n") != null);
}

test "formatter wraps long call expression at narrow printWidth" {
    const source = "console.log('a', 'b', 'c', 'd', 'e')";

    const wide = try linter.format(source, .{ .semi = true, .singleQuote = true, .printWidth = 120 }, std.testing.allocator);
    defer std.testing.allocator.free(wide);
    try std.testing.expectEqualStrings("console.log('a', 'b', 'c', 'd', 'e');", wide);

    const narrow = try linter.format(source, .{ .semi = true, .singleQuote = true, .printWidth = 30 }, std.testing.allocator);
    defer std.testing.allocator.free(narrow);
    try std.testing.expect(std.mem.indexOf(u8, narrow, "\n") != null);
}

test "formatter wraps long function params at narrow printWidth" {
    const source = "function demo(a: number, b: string, c: boolean, d: any) {}";

    const wide = try linter.format(source, .{ .semi = true, .printWidth = 120 }, std.testing.allocator);
    defer std.testing.allocator.free(wide);
    try std.testing.expectEqualStrings("function demo(a: number, b: string, c: boolean, d: any) {}", wide);

    const narrow = try linter.format(source, .{ .semi = true, .printWidth = 30 }, std.testing.allocator);
    defer std.testing.allocator.free(narrow);
    try std.testing.expect(std.mem.indexOf(u8, narrow, "\n") != null);
}

test "formatter idempotency with narrow printWidth" {
    const alloc = std.testing.allocator;
    const source =
        \\const data = { name: 'Luciano', age: 27, city: 'SP', country: 'Brazil' }
    ;

    const formatted1 = try linter.format(source, .{ .singleQuote = true, .semi = false, .printWidth = 30, .tabWidth = 2 }, alloc);
    defer alloc.free(formatted1);

    const formatted2 = try linter.format(formatted1, .{ .singleQuote = true, .semi = false, .printWidth = 30, .tabWidth = 2 }, alloc);
    defer alloc.free(formatted2);

    try std.testing.expect(std.mem.eql(u8, formatted1, formatted2));
}

test "proseWrap preserve keeps long lines unchanged" {
    const source =
        \\const data = { name: 'Ana', age: 30, city: 'SP', country: 'BR' }
    ;
    const out = try linter.format(source, .{ .singleQuote = true, .semi = false, .printWidth = 30, .proseWrap = .preserve }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "name: 'Ana'") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "country: 'BR'") != null);
}

test "proseWrap default is preserve" {
    const opts: common.FormatterOptions = .{};
    try std.testing.expectEqual(common.ProseWrap.preserve, opts.proseWrap);
}

test "proseWrap config parsing" {

    var cfg = try linter.parseConfig(
        \\{
        \\  "formatter": {
        \\    "proseWrap": "always"
        \\  }
        \\}
    , std.testing.allocator);
    defer cfg.deinit(std.testing.allocator);
    try std.testing.expectEqual(common.ProseWrap.always, cfg.formatter.options.proseWrap);
}

test "proseWrap never config parsing" {

    var cfg = try linter.parseConfig(
        \\{
        \\  "formatter": {
        \\    "proseWrap": "never"
        \\  }
        \\}
    , std.testing.allocator);
    defer cfg.deinit(std.testing.allocator);
    try std.testing.expectEqual(common.ProseWrap.never, cfg.formatter.options.proseWrap);
}

test "proseWrap invalid config falls back to preserve" {

    var cfg = try linter.parseConfig(
        \\{
        \\  "formatter": {
        \\    "proseWrap": "invalid"
        \\  }
        \\}
    , std.testing.allocator);
    defer cfg.deinit(std.testing.allocator);
    try std.testing.expectEqual(common.ProseWrap.preserve, cfg.formatter.options.proseWrap);
}

test "proseWrap always wraps fallback formatter lines at printWidth" {
    const source =
        \\This is a very long line of text that should be wrapped when proseWrap is set to always and printWidth is small enough to trigger wrapping.
    ;
    const out = try linter.format(source, .{ .semi = false, .printWidth = 40, .proseWrap = .always }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.count(u8, out, "\n") >= 2);
}

test "proseWrap never merges prose lines" {
    const source =
        \\This is the first line.
        \\This is the second line.
        \\This is the third line.
    ;
    const out = try linter.format(source, .{ .semi = false, .printWidth = 80, .proseWrap = .never }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.count(u8, out, "\n") <= 1);
}

test "proseWrap never stays as single line" {
    const source =
        \\This is a paragraph that should be on one line when proseWrap is set to never.
    ;
    const out = try linter.format(source, .{ .semi = false, .printWidth = 80, .proseWrap = .never }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.count(u8, out, "\n") <= 1);
}

test "proseWrap idempotent with fallback path" {
    const alloc = std.testing.allocator;
    const source =
        \\Some plain text content that goes through the fallback formatter path.
    ;
    const opts: common.FormatterOptions = .{ .semi = false, .printWidth = 40, .proseWrap = .always };
    const formatted1 = try linter.format(source, opts, alloc);
    defer alloc.free(formatted1);

    const formatted2 = try linter.format(formatted1, opts, alloc);
    defer alloc.free(formatted2);

    try std.testing.expect(std.mem.eql(u8, formatted1, formatted2));
}

test "objectWrap preserve keeps multiline object when source has newline" {
    const source =
        \\const obj = {
        \\  name: 'Ana'
        \\}
    ;
    const out = try linter.format(source, .{ .singleQuote = true, .semi = false, .printWidth = 120, .objectWrap = .preserve, .trailingComma = .none }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(source, out);
}

test "objectWrap collapse flattens object with newline" {
    const source =
        \\const obj = {
        \\  name: 'Ana'
        \\}
    ;
    const out = try linter.format(source, .{ .singleQuote = true, .semi = false, .printWidth = 120, .objectWrap = .collapse }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("const obj = { name: 'Ana' }", out);
}

test "objectWrap preserve keeps single-line object when source is single-line" {
    const source = "const obj = { name: 'Ana' }";
    const out = try linter.format(source, .{ .singleQuote = true, .semi = false, .printWidth = 120, .objectWrap = .preserve }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(source, out);
}

test "objectWrap preserve still wraps long object that exceeds printWidth" {
    const source =
        \\const data = { name: 'Ana', age: 30, city: 'SP', country: 'BR' }
    ;
    const out = try linter.format(source, .{ .singleQuote = true, .semi = false, .printWidth = 30, .tabWidth = 2, .objectWrap = .preserve }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "name: 'Ana'") != null);
}

test "objectWrap collapse keeps single-line object when source is multiline but fits" {
    const source =
        \\const obj = {
        \\  name: 'Ana'
        \\}
    ;
    const out = try linter.format(source, .{ .singleQuote = true, .semi = false, .printWidth = 120, .objectWrap = .collapse }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("const obj = { name: 'Ana' }", out);
}

test "objectWrap collapse still wraps when object exceeds printWidth" {
    const source =
        \\const data = {
        \\  name: 'Ana',
        \\  age: 30,
        \\  city: 'SP',
        \\  country: 'BR'
        \\}
    ;
    const out = try linter.format(source, .{ .singleQuote = true, .semi = false, .printWidth = 30, .tabWidth = 2, .objectWrap = .collapse }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "\n") != null);
}

test "objectWrap preserve idempotent on second pass" {
    const alloc = std.testing.allocator;
    const source =
        \\const obj = {
        \\  name: 'Ana'
        \\}
    ;
    const formatted1 = try linter.format(source, .{ .singleQuote = true, .semi = false, .printWidth = 120, .objectWrap = .preserve }, alloc);
    defer alloc.free(formatted1);

    const formatted2 = try linter.format(formatted1, .{ .singleQuote = true, .semi = false, .printWidth = 120, .objectWrap = .preserve }, alloc);
    defer alloc.free(formatted2);

    try std.testing.expect(std.mem.eql(u8, formatted1, formatted2));
}

test "objectWrap collapse idempotent on second pass" {
    const alloc = std.testing.allocator;
    const source =
        \\const obj = {
        \\  name: 'Ana'
        \\}
    ;
    const formatted1 = try linter.format(source, .{ .singleQuote = true, .semi = false, .printWidth = 120, .objectWrap = .collapse }, alloc);
    defer alloc.free(formatted1);

    const formatted2 = try linter.format(formatted1, .{ .singleQuote = true, .semi = false, .printWidth = 120, .objectWrap = .collapse }, alloc);
    defer alloc.free(formatted2);

    try std.testing.expect(std.mem.eql(u8, formatted1, formatted2));
}

test "objectWrap default is preserve" {
    const opts: common.FormatterOptions = .{};
    try std.testing.expectEqual(common.ObjectWrap.preserve, opts.objectWrap);
}

test "objectWrap config parsing" {

    var cfg = try linter.parseConfig(
        \\{
        \\  "formatter": {
        \\    "objectWrap": "collapse"
        \\  }
        \\}
    , std.testing.allocator);
    defer cfg.deinit(std.testing.allocator);
    try std.testing.expectEqual(common.ObjectWrap.collapse, cfg.formatter.options.objectWrap);
}

test "objectWrap invalid config falls back to preserve" {

    var cfg = try linter.parseConfig(
        \\{
        \\  "formatter": {
        \\    "objectWrap": "invalid"
        \\  }
        \\}
    , std.testing.allocator);
    defer cfg.deinit(std.testing.allocator);
    try std.testing.expectEqual(common.ObjectWrap.preserve, cfg.formatter.options.objectWrap);
}

test "operatorPosition end keeps operator at end of line when wrapping" {
    const source =
        \\let result = long_variable_name_here + another_long_variable_name;
    ;
    const out = try linter.format(source, .{
        .semi = true, .printWidth = 40, .operatorPosition = .end
    }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, " +\n") != null);
}

test "operatorPosition start puts operator at start of next line when wrapping" {
    const source =
        \\let result = long_variable_name_here + another_long_variable_name;
    ;
    const out = try linter.format(source, .{
        .semi = true, .printWidth = 40, .operatorPosition = .start
    }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "\n  + ") != null);
}

test "operatorPosition end no wrapping when fits on line" {
    const source =
        \\let result = a + b;
    ;
    const out = try linter.format(source, .{
        .semi = true, .printWidth = 80, .operatorPosition = .end
    }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(
        \\let result = a + b;
    , out);
}

test "operatorPosition start no wrapping when fits on line" {
    const source =
        \\let result = a + b;
    ;
    const out = try linter.format(source, .{
        .semi = true, .printWidth = 80, .operatorPosition = .start
    }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(
        \\let result = a + b;
    , out);
}

test "operatorPosition end idempotent" {
    const source =
        \\let result = long_variable_name_here + another_long_variable_name;
    ;
    const out = try linter.format(source, .{
        .semi = true, .printWidth = 40, .operatorPosition = .end
    }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    const out2 = try linter.format(out, .{
        .semi = true, .printWidth = 40, .operatorPosition = .end
    }, std.testing.allocator);
    defer std.testing.allocator.free(out2);
    try std.testing.expectEqualStrings(out, out2);
}

test "operatorPosition start idempotent" {
    const source =
        \\let result = long_variable_name_here + another_long_variable_name;
    ;
    const out = try linter.format(source, .{
        .semi = true, .printWidth = 40, .operatorPosition = .start
    }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    const out2 = try linter.format(out, .{
        .semi = true, .printWidth = 40, .operatorPosition = .start
    }, std.testing.allocator);
    defer std.testing.allocator.free(out2);
    try std.testing.expectEqualStrings(out, out2);
}

test "operatorPosition end with equality operator" {
    const source =
        \\let result = some_long_variable_name === another_long_variable_name;
    ;
    const out = try linter.format(source, .{
        .semi = true, .printWidth = 40, .operatorPosition = .end
    }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, " ===\n") != null);
}

test "operatorPosition start with equality operator" {
    const source =
        \\let result = some_long_variable_name === another_long_variable_name;
    ;
    const out = try linter.format(source, .{
        .semi = true, .printWidth = 40, .operatorPosition = .start
    }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "\n  === ") != null);
}

test "operatorPosition defaults to end" {
    const opts: common.FormatterOptions = .{};
    try std.testing.expectEqual(.end, opts.operatorPosition);
}

test "operatorPosition config parsing" {

    var cfg = try linter.parseConfig(
        \\{
        \\  "formatter": {
        \\    "operatorPosition": "start"
        \\  }
        \\}
    , std.testing.allocator);
    defer cfg.deinit(std.testing.allocator);
    try std.testing.expectEqual(.start, cfg.formatter.options.operatorPosition);
}

test "ternaryStyle classic wraps with ? and : indented on new lines" {
    const source =
        \\let result = some_very_long_condition ? consequent_value : alternate_value;
    ;
    const out = try linter.format(source, .{
        .semi = true, .printWidth = 40, .ternaryStyle = .classic
    }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "\n  ? ") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\n  : ") != null);
}

test "ternaryStyle linear wraps with ? and : at end of lines" {
    const source =
        \\let result = some_very_long_condition ? consequent_value : alternate_value;
    ;
    const out = try linter.format(source, .{
        .semi = true, .printWidth = 40, .ternaryStyle = .linear
    }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, " ?\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, " :\n") != null);
}

test "ternaryStyle classic inline when fits on line" {
    const source =
        \\let result = a ? b : c;
    ;
    const out = try linter.format(source, .{
        .semi = true, .printWidth = 80, .ternaryStyle = .classic
    }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(
        \\let result = a ? b : c;
    , out);
}

test "ternaryStyle linear inline when fits on line" {
    const source =
        \\let result = a ? b : c;
    ;
    const out = try linter.format(source, .{
        .semi = true, .printWidth = 80, .ternaryStyle = .linear
    }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(
        \\let result = a ? b : c;
    , out);
}

test "ternaryStyle classic idempotent" {
    const source =
        \\let result = some_very_long_condition ? consequent_value : alternate_value;
    ;
    const out = try linter.format(source, .{
        .semi = true, .printWidth = 40, .ternaryStyle = .classic
    }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    const out2 = try linter.format(out, .{
        .semi = true, .printWidth = 40, .ternaryStyle = .classic
    }, std.testing.allocator);
    defer std.testing.allocator.free(out2);
    try std.testing.expectEqualStrings(out, out2);
}

test "ternaryStyle linear idempotent" {
    const source =
        \\let result = some_very_long_condition ? consequent_value : alternate_value;
    ;
    const out = try linter.format(source, .{
        .semi = true, .printWidth = 40, .ternaryStyle = .linear
    }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    const out2 = try linter.format(out, .{
        .semi = true, .printWidth = 40, .ternaryStyle = .linear
    }, std.testing.allocator);
    defer std.testing.allocator.free(out2);
    try std.testing.expectEqualStrings(out, out2);
}

test "ternaryStyle classic normalizes linear input" {
    const source =
        \\let result = some_very_long_condition ?
        \\  consequent_value :
        \\  alternate_value;
    ;
    const out = try linter.format(source, .{
        .semi = true, .printWidth = 40, .ternaryStyle = .classic
    }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "\n  ? ") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\n  : ") != null);
}

test "ternaryStyle linear normalizes classic input" {
    const source =
        \\let result = some_very_long_condition
        \\  ? consequent_value
        \\  : alternate_value;
    ;
    const out = try linter.format(source, .{
        .semi = true, .printWidth = 40, .ternaryStyle = .linear
    }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, " ?\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, " :\n") != null);
}

test "ternaryStyle defaults to classic" {
    const opts: common.FormatterOptions = .{};
    try std.testing.expectEqual(.classic, opts.ternaryStyle);
}

test "ternaryStyle config parsing" {

    var cfg = try linter.parseConfig(
        \\{
        \\  "formatter": {
        \\    "ternaryStyle": "linear"
        \\  }
        \\}
    , std.testing.allocator);
    defer cfg.deinit(std.testing.allocator);
    try std.testing.expectEqual(.linear, cfg.formatter.options.ternaryStyle);
}

test "blank line preserved before comment between statements" {
    const alloc = std.testing.allocator;
    const source =
        \\console.log(1)
        \\
        \\/** comment */
        \\const a = 2
    ;
    const out = try linter.format(source, .{ .semi = false, .singleQuote = true }, alloc);
    defer alloc.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "console.log(1)\n\n/**") != null);
}

test "blank line preserved after comment between statements" {
    const alloc = std.testing.allocator;
    const source =
        \\console.log(1)
        \\/** comment */
        \\
        \\const a = 2
    ;
    const out = try linter.format(source, .{ .semi = false, .singleQuote = true }, alloc);
    defer alloc.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "*/\n\nconst") != null);
}

test "blank lines preserved around function with comments" {
    const alloc = std.testing.allocator;
    const source =
        \\console.log(1)
        \\
        \\/** comment */
        \\function aaa() {}
        \\
        \\/** comment 2 */
        \\console.log(2)
    ;
    const out = try linter.format(source, .{ .semi = false, .singleQuote = true }, alloc);
    defer alloc.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "console.log(1)\n\n/**") != null);
}

test "exact blank line preservation: no blank lines between statements" {
    const alloc = std.testing.allocator;
    const source =
        \\console.log(arr, newArr, sum(4), obj.name)
        \\/** dummy */
        \\function aaa() {
        \\  /** dummy */
        \\  return 1000 /** dummy */
        \\  /** dummy */
        \\}
        \\/** dummy */
        \\const bbb = aaa()
        \\console.log(bbb)
    ;
    const out = try linter.format(source, .{ .semi = false, .singleQuote = true }, alloc);
    defer alloc.free(out);
    const expected =
        \\console.log(arr, newArr, sum(4), obj.name)
        \\/** dummy */
        \\function aaa() {
        \\  /** dummy */
        \\  return 1000 /** dummy */
        \\  /** dummy */
        \\}
        \\/** dummy */
        \\const bbb = aaa()
        \\console.log(bbb)
    ;
    try std.testing.expectEqualStrings(expected, out);
}

test "exact blank line preservation: one blank line between statements" {
    const alloc = std.testing.allocator;
    const source =
        \\console.log(arr, newArr, sum(4), obj.name)
        \\
        \\/** dummy */
        \\function aaa() {
        \\  /** dummy */
        \\  return 1000 /** dummy */
        \\  /** dummy */
        \\}
        \\/** dummy */
        \\
        \\const bbb = aaa()
        \\console.log(bbb)
    ;
    const out = try linter.format(source, .{ .semi = false, .singleQuote = true }, alloc);
    defer alloc.free(out);
    const expected =
        \\console.log(arr, newArr, sum(4), obj.name)
        \\
        \\/** dummy */
        \\function aaa() {
        \\  /** dummy */
        \\  return 1000 /** dummy */
        \\  /** dummy */
        \\}
        \\/** dummy */
        \\
        \\const bbb = aaa()
        \\console.log(bbb)
    ;
    try std.testing.expectEqualStrings(expected, out);
}

test "exact blank line preservation: two blank lines between statements" {
    const alloc = std.testing.allocator;
    const source =
        \\const a = 1
        \\
        \\
        \\const b = 2
    ;
    const out = try linter.format(source, .{ .semi = false, .singleQuote = true }, alloc);
    defer alloc.free(out);
    const expected =
        \\const a = 1
        \\
        \\
        \\const b = 2
    ;
    try std.testing.expectEqualStrings(expected, out);
}

test "exact blank line preservation: blank line between function declarations" {
    const alloc = std.testing.allocator;
    const source =
        \\function foo() {
        \\  return 1
        \\}
        \\
        \\function bar() {
        \\  return 2
        \\}
    ;
    const out = try linter.format(source, .{ .semi = false, .singleQuote = true }, alloc);
    defer alloc.free(out);
    const expected =
        \\function foo() {
        \\  return 1
        \\}
        \\
        \\function bar() {
        \\  return 2
        \\}
    ;
    try std.testing.expectEqualStrings(expected, out);
}

test "exact blank line preservation: no blank line between consecutive statements" {
    const alloc = std.testing.allocator;
    const source =
        \\const a = 1
        \\const b = 2
        \\const c = 3
    ;
    const out = try linter.format(source, .{ .semi = false, .singleQuote = true }, alloc);
    defer alloc.free(out);
    const expected =
        \\const a = 1
        \\const b = 2
        \\const c = 3
    ;
    try std.testing.expectEqualStrings(expected, out);
}

test "exact blank line preservation: comments inside block body" {
    const alloc = std.testing.allocator;
    const source =
        \\function aaa() {
        \\  /** before return */
        \\  return 1000
        \\  /** after return */
        \\}
    ;
    const out = try linter.format(source, .{ .semi = false, .singleQuote = true }, alloc);
    defer alloc.free(out);
    const expected =
        \\function aaa() {
        \\  /** before return */
        \\  return 1000
        \\  /** after return */
        \\}
    ;
    try std.testing.expectEqualStrings(expected, out);
}

test "exact blank line preservation: blank line inside block body" {
    const alloc = std.testing.allocator;
    const source =
        \\function aaa() {
        \\  const x = 1
        \\
        \\  return x
        \\}
    ;
    const out = try linter.format(source, .{ .semi = false, .singleQuote = true }, alloc);
    defer alloc.free(out);
    const expected =
        \\function aaa() {
        \\  const x = 1
        \\
        \\  return x
        \\}
    ;
    try std.testing.expectEqualStrings(expected, out);
}

test "exact blank line preservation: inline comment does not add blank line" {
    const alloc = std.testing.allocator;
    const source =
        \\const a = 1 // inline
        \\const b = 2
    ;
    const out = try linter.format(source, .{ .semi = false, .singleQuote = true }, alloc);
    defer alloc.free(out);
    const expected =
        \\const a = 1 // inline
        \\const b = 2
    ;
    try std.testing.expectEqualStrings(expected, out);
}

test "exact blank line preservation: line comment between statements" {
    const alloc = std.testing.allocator;
    const source =
        \\const a = 1
        \\// comment
        \\const b = 2
    ;
    const out = try linter.format(source, .{ .semi = false, .singleQuote = true }, alloc);
    defer alloc.free(out);
    const expected =
        \\const a = 1
        \\// comment
        \\const b = 2
    ;
    try std.testing.expectEqualStrings(expected, out);
}

test "exact blank line preservation: blank line before line comment" {
    const alloc = std.testing.allocator;
    const source =
        \\const a = 1
        \\
        \\// comment
        \\const b = 2
    ;
    const out = try linter.format(source, .{ .semi = false, .singleQuote = true }, alloc);
    defer alloc.free(out);
    const expected =
        \\const a = 1
        \\
        \\// comment
        \\const b = 2
    ;
    try std.testing.expectEqualStrings(expected, out);
}

test "blank line after comment before next statement" {
    const alloc = std.testing.allocator;
    const source =
        \\const a = 1
        \\// comment
        \\
        \\const b = 2
    ;
    const out = try linter.format(source, .{ .semi = false, .singleQuote = true }, alloc);
    defer alloc.free(out);
    const expected =
        \\const a = 1
        \\// comment
        \\
        \\const b = 2
    ;
    try std.testing.expectEqualStrings(expected, out);
}

test "blank line after block comment before next statement" {
    const alloc = std.testing.allocator;
    const source =
        \\function aaa() {
        \\  return 1
        \\}
        \\/** dummy */
        \\
        \\const bbb = aaa()
    ;
    const out = try linter.format(source, .{ .semi = false, .singleQuote = true }, alloc);
    defer alloc.free(out);
    const expected =
        \\function aaa() {
        \\  return 1
        \\}
        \\/** dummy */
        \\
        \\const bbb = aaa()
    ;
    try std.testing.expectEqualStrings(expected, out);
}

test "blank line before AND after comment between statements" {
    const alloc = std.testing.allocator;
    const source =
        \\const a = 1
        \\
        \\/** comment */
        \\
        \\const b = 2
    ;
    const out = try linter.format(source, .{ .semi = false, .singleQuote = true }, alloc);
    defer alloc.free(out);
    const expected =
        \\const a = 1
        \\
        \\/** comment */
        \\
        \\const b = 2
    ;
    try std.testing.expectEqualStrings(expected, out);
}

test "multiple comments with blank lines between them" {
    const alloc = std.testing.allocator;
    const source =
        \\const a = 1
        \\/** first */
        \\
        \\/** second */
        \\const b = 2
    ;
    const out = try linter.format(source, .{ .semi = false, .singleQuote = true }, alloc);
    defer alloc.free(out);
    const expected =
        \\const a = 1
        \\/** first */
        \\
        \\/** second */
        \\const b = 2
    ;
    try std.testing.expectEqualStrings(expected, out);
}

test "idempotent formatting with blank lines" {
    const alloc = std.testing.allocator;
    const source =
        \\console.log(arr, newArr, sum(4), obj.name)
        \\/** dummy */
        \\function aaa() {
        \\  /** dummy */
        \\  return 1000 /** dummy */
        \\  /** dummy */
        \\}
        \\/** dummy */
        \\const bbb = aaa()
        \\console.log(bbb)
    ;
    const out1 = try linter.format(source, .{ .semi = false, .singleQuote = true }, alloc);
    defer alloc.free(out1);
    const out2 = try linter.format(out1, .{ .semi = false, .singleQuote = true }, alloc);
    defer alloc.free(out2);
    try std.testing.expectEqualStrings(out1, out2);
}

test "idempotent formatting with blank lines around comments" {
    const alloc = std.testing.allocator;
    const source =
        \\const a = 1
        \\
        \\/** comment */
        \\
        \\const b = 2
    ;
    const out1 = try linter.format(source, .{ .semi = false, .singleQuote = true }, alloc);
    defer alloc.free(out1);
    const out2 = try linter.format(out1, .{ .semi = false, .singleQuote = true }, alloc);
    defer alloc.free(out2);
    try std.testing.expectEqualStrings(out1, out2);
}

test "no extra blank line after closing brace" {
    const alloc = std.testing.allocator;
    const source =
        \\function aaa() {
        \\  return 1
        \\}
        \\const b = aaa()
    ;
    const out = try linter.format(source, .{ .semi = false, .singleQuote = true }, alloc);
    defer alloc.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "}\n\nconst") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "}\nconst") != null);
}

test "no extra blank line after closing brace with comment" {
    const alloc = std.testing.allocator;
    const source =
        \\function aaa() {
        \\  return 1
        \\}
        \\/** comment */
        \\const b = aaa()
    ;
    const out = try linter.format(source, .{ .semi = false, .singleQuote = true }, alloc);
    defer alloc.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "}\n\n/**") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "}\n/**") != null);
}

test "objectWrap preserve wraps parent when nested object is multiline" {
    const source =
        \\const obj = { name: 'Luciano', age: 24, work: 'Software Engineer', address: {
        \\  street: 'Aaaaaa',
        \\  neighborhood: ''
        \\}, actived: true }
    ;
    const out = try linter.format(source, .{ .singleQuote = true, .semi = false, .trailingComma = .all, .objectWrap = .preserve }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "\n  name: 'Luciano',") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\n  address: {") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\n    street: 'Aaaaaa',") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\n    neighborhood: '',") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\n  },") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\n  actived: true,") != null);
    try std.testing.expect(out[out.len - 1] == '}');
}

test "objectWrap preserve idempotent with nested multiline object" {
    const alloc = std.testing.allocator;
    const source =
        \\const obj = { name: 'Luciano', age: 24, address: {
        \\  street: 'Aaaaaa',
        \\  neighborhood: ''
        \\}, actived: true }
    ;
    const opts = common.FormatterOptions{ .singleQuote = true, .semi = false, .trailingComma = .all, .objectWrap = .preserve };
    const out1 = try linter.format(source, opts, alloc);
    defer alloc.free(out1);
    const out2 = try linter.format(out1, opts, alloc);
    defer alloc.free(out2);
    try std.testing.expectEqualStrings(out1, out2);
}

test "objectWrap preserve deeply nested object causes all parents to wrap" {
    const source =
        \\const obj = { a: 1, b: { c: 2, d: {
        \\  e: 3
        \\} } }
    ;
    const out = try linter.format(source, .{ .singleQuote = true, .semi = false, .objectWrap = .preserve }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "\n  a: 1,") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\n  b: {") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\n    c: 2,") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\n    d: {") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\n      e: 3,") != null);
}

test "objectWrap collapse still works correctly with nested objects" {
    const source =
        \\const obj = {
        \\  name: 'Ana',
        \\  address: {
        \\    street: 'Rua X'
        \\  }
        \\}
    ;
    const out = try linter.format(source, .{ .singleQuote = true, .semi = false, .printWidth = 120, .objectWrap = .collapse }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("const obj = { name: 'Ana', address: { street: 'Rua X' } }", out);
}

test "objectWrap preserve nested object with spread" {
    const source =
        \\const obj = { a: 1, ...{
        \\  b: 2
        \\} }
    ;
    const out = try linter.format(source, .{ .singleQuote = true, .semi = false, .objectWrap = .preserve }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "\n  a: 1,") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\n  ...{") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\n    b: 2,") != null);
}

test "objectWrap idempotent single-pass with nested object in single-line source" {
    const alloc = std.testing.allocator;
    const source = "const obj = { name: 'Luciano', age: 24, work: 'Software Engineer', address: { street: 'Aaaaaa', neighborhood: '' }, actived: true }";
    const formatted1 = try linter.format(source, .{ .singleQuote = true, .semi = false, .trailingComma = .all }, alloc);
    defer alloc.free(formatted1);
    const formatted2 = try linter.format(formatted1, .{ .singleQuote = true, .semi = false, .trailingComma = .all }, alloc);
    defer alloc.free(formatted2);
    try std.testing.expect(std.mem.eql(u8, formatted1, formatted2));
    try std.testing.expect(std.mem.indexOf(u8, formatted1, "\n  name: 'Luciano',") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted1, "\n  address: {") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted1, "\n  actived: true,") != null);
    try std.testing.expect(formatted1[formatted1.len - 1] == '}');
}
