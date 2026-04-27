const std = @import("std");

const compiler = @import("compiler");
const util = @import("../util.zig");

const expectContainsText = util.expectContainsText;

test "ts elide: decorator metadata does not keep type-only parameter import" {
    const source =
        \\import { Post, Body } from "@nestjs/common";
        \\import { CreateNotificationBody } from "../requests/create-notification-body.js";
        \\
        \\class NotificationsController {
        \\  @Post()
        \\  async create(@Body() body: CreateNotificationBody): Promise<any> {
        \\    return body;
        \\  }
        \\}
    ;

    var cfg = compiler.Config{};
    cfg.parser.syntax = .typescript;
    cfg.parser.decorators = true;
    cfg.transform.legacy_decorator = true;
    cfg.transform.decorator_metadata = true;

    const result = try compiler.compile(
        source,
        "test.ts",
        cfg,
        std.testing.io,
        std.testing.allocator,
    );
    defer result.deinit(std.testing.allocator);

    try expectContainsText(result.code, "import { Post, Body } from \"@nestjs/common\"");
    try std.testing.expect(std.mem.indexOf(u8, result.code, "create-notification-body") == null);
    try std.testing.expect(std.mem.indexOf(u8, result.code, "import { CreateNotificationBody }") == null);
    try expectContainsText(result.code, "typeof CreateNotificationBody === \"undefined\" ? Object : CreateNotificationBody");
}
