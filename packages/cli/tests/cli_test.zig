const std = @import("std");

const cli = @import("cli");

test "cli package exposes command-oriented compile path helpers" {
    try std.testing.expect(cli.isTranspilable("index.ts"));
    try std.testing.expectEqual(cli.Command.compile, cli.Command.compile);
}
