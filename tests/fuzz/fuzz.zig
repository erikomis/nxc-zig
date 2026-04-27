const std = @import("std");
const compiler = @import("compiler");

const keywords = [_][]const u8{
    "let", "const", "var", "function", "return", "if", "else", "for",
    "while", "do", "switch", "case", "break", "continue", "try", "catch",
    "finally", "throw", "new", "this", "typeof", "void", "delete", "in",
    "of", "class", "extends", "super", "import", "export", "from", "as",
    "yield", "async", "await", "true", "false", "null", "undefined",
    "console", "log", "x", "y", "z", "foo", "bar", "baz",
    "a", "b", "c", "i", "j", "k", "n", "length", "name", "value",
    "+", "-", "*", "/", "%", "==", "!=", "<", ">", "<=", ">=",
    "&&", "||", "!", "(", ")", "{", "}", "[", "]", ";", ",",
    ".", "=", "+=", "-=", "=>", ":", "?", "??",
};

pub fn generateSource(rng: std.Random, alloc: std.mem.Allocator) ![]u8 {
    var buf = std.ArrayListUnmanaged(u8).empty;
    errdefer buf.deinit(alloc);

    const num_tokens = rng.intRangeAtMost(usize, 1, 50);
    for (0..num_tokens) |_| {
        const word = keywords[rng.int(usize) % keywords.len];
        try buf.appendSlice(alloc, word);
        try buf.append(alloc, ' ');
    }

    return buf.toOwnedSlice(alloc);
}

test "fuzz simple random sources" {
    const alloc = std.testing.allocator;
    var seed: u64 = 42;

    for (0..100) |_| {
        seed = seed *% 6364136223846793005 +% 1442695040888963407;
        var prng = std.Random.DefaultPrng.init(seed);
        const rng = prng.random();

        const source = generateSource(rng, alloc) catch continue;
        defer alloc.free(source);

        var cfg = compiler.Config{};
        cfg.parser.syntax = .ecmascript;
        cfg.jsx = false;
        cfg.check = false;

        if (compiler.compile(source, "fuzz.js", cfg, std.testing.io, alloc)) |result| {
            result.deinit(alloc);
        } else |_| continue;
    }
}
