const std = @import("std");
const h = @import("harness");
const linter = @import("linter");

test "embeddedLanguageFormatting off preserves template literal content as-is" {
    const source =
        \\let s = `hello ${name} world`;
    ;
    const out = try linter.format(source, .{
        .semi = true, .embeddedLanguageFormatting = .off
    }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(source, out);
}

test "embeddedLanguageFormatting auto formats expressions inside template literals" {
    const source =
        \\let s = `hello ${ name  } world`;
    ;
    const out = try linter.format(source, .{
        .semi = true, .embeddedLanguageFormatting = .auto
    }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(
        \\let s = `hello ${name} world`;
    , out);
}

test "embeddedLanguageFormatting off skips formatting tagged templates" {
    const source =
        \\const html = html`<div>${ name  }</div>`;
    ;
    const out = try linter.format(source, .{
        .semi = true, .embeddedLanguageFormatting = .off
    }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(source, out);
}

test "embeddedLanguageFormatting auto formats tagged template expressions" {
    const source =
        \\const html = html`<div>${ name  }</div>`;
    ;
    const out = try linter.format(source, .{
        .semi = true, .embeddedLanguageFormatting = .auto
    }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(
        \\const html = html`<div>${name}</div>`;
    , out);
}

test "embeddedLanguageFormatting off multi-expression template" {
    const source =
        \\let s = `${ a  } + ${ b  } = ${ c  }`;
    ;
    const out = try linter.format(source, .{
        .semi = true, .embeddedLanguageFormatting = .off
    }, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(source, out);
}

test "embeddedLanguageFormatting defaults to auto" {
    const opts: @import("common").FormatterOptions = .{};
    try std.testing.expectEqual(.auto, opts.embeddedLanguageFormatting);
}

test "embeddedLanguageFormatting config parsing" {

    var cfg = try linter.parseConfig(
        \\{
        \\  "formatter": {
        \\    "embeddedLanguageFormatting": "off"
        \\  }
        \\}
    , std.testing.allocator);
    defer cfg.deinit(std.testing.allocator);
    try std.testing.expectEqual(.off, cfg.formatter.options.embeddedLanguageFormatting);
}
