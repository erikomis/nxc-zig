const std = @import("std");
const h = @import("harness");
const linter = @import("linter");

test "singleAttributePerLine false keeps attrs inline" {
    const source = "<div class=\"foo\" id=\"bar\" x-data=\"test\"></div>";
    const out = try linter.format(source, .{ .semi = false, .singleAttributePerLine = false, .printWidth = 120 }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(source, out);
}

test "singleAttributePerLine true puts attrs on separate lines" {
    const source = "<div class=\"foo\" id=\"bar\" x-data=\"test\"></div>";
    const out = try linter.format(source, .{ .semi = false, .singleAttributePerLine = true, .printWidth = 120 }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.count(u8, out, "\n") >= 3);
    try std.testing.expect(std.mem.indexOf(u8, out, "class=\"foo\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "id=\"bar\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "x-data=\"test\"") != null);
}

test "singleAttributePerLine true self-closing with attrs" {
    const source = "<input type=\"text\" name=\"email\" placeholder=\"Enter email\" />";
    const out = try linter.format(source, .{ .semi = false, .singleAttributePerLine = true, .printWidth = 120 }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.count(u8, out, "\n") >= 3);
    try std.testing.expect(std.mem.indexOf(u8, out, "type=\"text\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "name=\"email\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "placeholder=\"Enter email\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "/>") != null);
}

test "singleAttributePerLine true single attr stays inline" {
    const source = "<div class=\"foo\"></div>";
    const out = try linter.format(source, .{ .semi = false, .singleAttributePerLine = true, .printWidth = 120 }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(source, out);
}

test "singleAttributePerLine true no attrs unchanged" {
    const source = "<div></div>";
    const out = try linter.format(source, .{ .semi = false, .singleAttributePerLine = true, .printWidth = 120 }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(source, out);
}

test "singleAttributePerLine idempotent on second pass" {
    const alloc = std.testing.allocator;
    const source = "<div class=\"foo\" id=\"bar\" x-data=\"test\"></div>";
    const formatted1 = try linter.format(source, .{ .semi = false, .singleAttributePerLine = true, .printWidth = 120 }, alloc);
    defer alloc.free(formatted1);

    const formatted2 = try linter.format(formatted1, .{ .semi = false, .singleAttributePerLine = true, .printWidth = 120 }, alloc);
    defer alloc.free(formatted2);

    try std.testing.expect(std.mem.eql(u8, formatted1, formatted2));
}

test "singleAttributePerLine default is false" {
    const opts: @import("common").FormatterOptions = .{};
    try std.testing.expectEqual(false, opts.singleAttributePerLine);
}

test "singleAttributePerLine config parsing" {

    var cfg = try linter.parseConfig(
        \\{
        \\  "formatter": {
        \\    "singleAttributePerLine": true
        \\  }
        \\}
    , std.testing.allocator);
    defer cfg.deinit(std.testing.allocator);
    try std.testing.expectEqual(true, cfg.formatter.options.singleAttributePerLine);
}

test "bracketSameLine true for multi-attr non-self-closing element" {
    const source =
        \\let el = <button
        \\  className="prettier-class"
        \\  id="prettier-id"
        \\  onClick={this.handleClick}>
        \\  Click Here
        \\</button>;
    ;
    const out = try linter.format(source, .{
        .semi = true, .singleAttributePerLine = true, .bracketSameLine = true
    }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(
        \\let el = <button
        \\  className="prettier-class"
        \\  id="prettier-id"
        \\  onClick={this.handleClick}>
        \\  Click Here
        \\</button>;
    , out);
}

test "bracketSameLine false for multi-attr non-self-closing element" {
    const source =
        \\let el = <button
        \\  className="prettier-class"
        \\  id="prettier-id"
        \\  onClick={this.handleClick}
        \\>
        \\  Click Here
        \\</button>;
    ;
    const out = try linter.format(source, .{
        .semi = true, .singleAttributePerLine = true, .bracketSameLine = false
    }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(
        \\let el = <button
        \\  className="prettier-class"
        \\  id="prettier-id"
        \\  onClick={this.handleClick}
        \\>
        \\  Click Here
        \\</button>;
    , out);
}

test "bracketSameLine false formats true-style input correctly" {
    const source =
        \\let el = <button
        \\  className="prettier-class"
        \\  id="prettier-id"
        \\  onClick={this.handleClick}>
        \\  Click Here
        \\</button>;
    ;
    const out = try linter.format(source, .{
        .semi = true, .singleAttributePerLine = true, .bracketSameLine = false
    }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(
        \\let el = <button
        \\  className="prettier-class"
        \\  id="prettier-id"
        \\  onClick={this.handleClick}
        \\>
        \\  Click Here
        \\</button>;
    , out);
}

test "bracketSameLine true formats false-style input correctly" {
    const source =
        \\let el = <button
        \\  className="prettier-class"
        \\  id="prettier-id"
        \\  onClick={this.handleClick}
        \\>
        \\  Click Here
        \\</button>;
    ;
    const out = try linter.format(source, .{
        .semi = true, .singleAttributePerLine = true, .bracketSameLine = true
    }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(
        \\let el = <button
        \\  className="prettier-class"
        \\  id="prettier-id"
        \\  onClick={this.handleClick}>
        \\  Click Here
        \\</button>;
    , out);
}

test "bracketSameLine true self-closing multi-attr element" {
    const source =
        \\let input = <input
        \\  type="text"
        \\  name="email" />;
    ;
    const out = try linter.format(source, .{
        .semi = true, .singleAttributePerLine = true, .bracketSameLine = true
    }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(
        \\let input = <input
        \\  type="text"
        \\  name="email" />;
    , out);
}

test "bracketSameLine false self-closing multi-attr element" {
    const source =
        \\let input = <input
        \\  type="text"
        \\  name="email"
        \\/>;
    ;
    const out = try linter.format(source, .{
        .semi = true, .singleAttributePerLine = true, .bracketSameLine = false
    }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(
        \\let input = <input
        \\  type="text"
        \\  name="email"
        \\/>;
    , out);
}

test "bracketSameLine single-attr element does not wrap" {
    const source =
        \\let el = <div class="foo">content</div>;
    ;
    const out = try linter.format(source, .{
        .semi = true, .singleAttributePerLine = true, .bracketSameLine = false
    }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(
        \\let el = <div class="foo">content</div>;
    , out);
}

test "bracketSameLine defaults to false (prettier-compatible)" {
    const opts: @import("common").FormatterOptions = .{};
    try std.testing.expectEqual(false, opts.bracketSameLine);
}

test "bracketSameLine config parsing" {

    var cfg = try linter.parseConfig(
        \\{
        \\  "formatter": {
        \\    "bracketSameLine": false
        \\  }
        \\}
    , std.testing.allocator);
    defer cfg.deinit(std.testing.allocator);
    try std.testing.expectEqual(false, cfg.formatter.options.bracketSameLine);
}

test "jsxSingleQuote true uses single quotes in JSX attrs" {
    const source =
        \\let el = <div class="foo" id="bar">text</div>;
    ;
    const out = try linter.format(source, .{
        .semi = true, .jsxSingleQuote = true
    }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(
        \\let el = <div class='foo' id='bar'>text</div>;
    , out);
}

test "jsxSingleQuote false uses double quotes in JSX attrs" {
    const source =
        \\let el = <div class='foo' id='bar'>text</div>;
    ;
    const out = try linter.format(source, .{
        .semi = true, .jsxSingleQuote = false
    }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(
        \\let el = <div class="foo" id="bar">text</div>;
    , out);
}

test "jsxSingleQuote default false keeps double quotes in JSX attrs" {
    const source =
        \\let el = <div class="foo">text</div>;
    ;
    const out = try linter.format(source, .{
        .semi = true
    }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(
        \\let el = <div class="foo">text</div>;
    , out);
}

test "jsxSingleQuote idempotent true" {
    const source =
        \\let el = <div class='foo' id='bar'>text</div>;
    ;
    const out = try linter.format(source, .{
        .semi = true, .jsxSingleQuote = true
    }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    const out2 = try linter.format(out, .{
        .semi = true, .jsxSingleQuote = true
    }, std.testing.allocator);
    defer std.testing.allocator.free(out2);
    try std.testing.expectEqualStrings(out, out2);
}

test "jsxSingleQuote false idempotent" {
    const source =
        \\let el = <div class="foo" id="bar">text</div>;
    ;
    const out = try linter.format(source, .{
        .semi = true, .jsxSingleQuote = false
    }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    const out2 = try linter.format(out, .{
        .semi = true, .jsxSingleQuote = false
    }, std.testing.allocator);
    defer std.testing.allocator.free(out2);
    try std.testing.expectEqualStrings(out, out2);
}

test "jsxSingleQuote does not affect regular string literals" {
    const source =
        \\let s = "hello world";
    ;
    const out = try linter.format(source, .{
        .semi = true, .jsxSingleQuote = true, .singleQuote = false
    }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(
        \\let s = "hello world";
    , out);
}

test "jsxSingleQuote with singleQuote true both respected" {
    const source =
        \\let s = 'hello';
        \\let el = <div class="foo">text</div>;
    ;
    const out = try linter.format(source, .{
        .semi = true, .singleQuote = true, .jsxSingleQuote = false
    }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(
        \\let s = 'hello';
        \\let el = <div class="foo">text</div>;
    , out);
}

test "jsxSingleQuote multi-attr with singleAttributePerLine" {
    const source =
        \\let el = <button
        \\  className="prettier-class"
        \\  id="prettier-id">
        \\  Click Here
        \\</button>;
    ;
    const out = try linter.format(source, .{
        .semi = true, .singleAttributePerLine = true, .jsxSingleQuote = true, .bracketSameLine = true
    }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(
        \\let el = <button
        \\  className='prettier-class'
        \\  id='prettier-id'>
        \\  Click Here
        \\</button>;
    , out);
}

test "jsxSingleQuote defaults to false" {
    const opts: @import("common").FormatterOptions = .{};
    try std.testing.expectEqual(false, opts.jsxSingleQuote);
}

test "jsxSingleQuote config parsing" {

    var cfg = try linter.parseConfig(
        \\{
        \\  "formatter": {
        \\    "jsxSingleQuote": true
        \\  }
        \\}
    , std.testing.allocator);
    defer cfg.deinit(std.testing.allocator);
    try std.testing.expectEqual(true, cfg.formatter.options.jsxSingleQuote);
}

test "regression: bracketSameLine default puts JSX closing bracket on its own line" {
    const source =
        \\let el = <button
        \\ className="prettier-class"
        \\ id="prettier-id"
        \\ onClick={this.handleClick}>
        \\ Click Here
        \\</button>;
    ;
    const out = try linter.format(source, .{
        .semi = true,
        .singleAttributePerLine = true,
        .bracketSameLine = false,
    }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expect(out.len > 0);
}

test "regression: bracketSameLine default is false matches prettier struct default" {
    const opts: @import("common").FormatterOptions = .{};
    try std.testing.expectEqual(false, opts.bracketSameLine);
}

test "regression: bracketSameLine true still works when explicitly set" {
    const source =
        \\let el = <button
        \\ className="prettier-class"
        \\ id="prettier-id"
        \\ onClick={this.handleClick}
        \\>
        \\ Click Here
        \\</button>;
    ;
    const out = try linter.format(source, .{
        .semi = true,
        .singleAttributePerLine = true,
        .bracketSameLine = true,
    }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expect(out.len > 0);
}

test "regression: trailingComma and bracketSameLine defaults together match prettier" {
    const source =
        \\const data = { name: 'Ana', age: 30, city: 'SP', country: 'BR' }
        \\let el = <button
        \\ className="prettier-class"
        \\ id="prettier-id"
        \\ onClick={this.handleClick}>
        \\ Click Here
        \\</button>;
    ;
    const out = try linter.format(source, .{
        .semi = true,
        .singleQuote = true,
        .singleAttributePerLine = true,
        .printWidth = 30,
        .tabWidth = 2,
        .trailingComma = .all,
        .bracketSameLine = false,
    }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "'BR',") != null);
    try std.testing.expect(out.len > 0);
}
