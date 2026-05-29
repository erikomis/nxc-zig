const std = @import("std");

const cli = @import("cli");
const linter = @import("linter");
const cache = @import("cache");
const watch = @import("watch");

fn nowMs() i64 {
    var tp: std.os.linux.timespec = undefined;
    _ = std.os.linux.clock_gettime(std.os.linux.CLOCK.MONOTONIC, &tp);
    return @as(i64, tp.sec) * 1000 + @divTrunc(@as(i64, tp.nsec), 1_000_000);
}

const usage =
    \\nxc-linter - lint source files
    \\
    \\Usage:
    \\  nxc-linter [--config <path>] [--fix] [--cache] [--watch] [--json] [--list-rules] [--verbose] [<file|dir> ...]
    \\
    \\If no paths given, lints all source files in the current directory recursively.
    \\
;

pub fn main(init: std.process.Init) !void {
    const alloc = init.gpa;
    const io = init.io;
    const args = try init.minimal.args.toSlice(alloc);
    defer alloc.free(args);

    var config_path: ?[]const u8 = null;
    var fix = false;
    var verbose = false;
    var enable_cache = false;
    var enable_watch = false;
    var json_output = false;
    var raw_paths = std.ArrayListUnmanaged([]const u8).empty;
    defer raw_paths.deinit(alloc);

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            try std.Io.File.stdout().writeStreamingAll(io, usage);
            return;
        } else if (std.mem.eql(u8, arg, "--config")) {
            i += 1;
            if (i >= args.len) fatal("--config requires value");
            config_path = args[i];
        } else if (std.mem.eql(u8, arg, "--fix")) {
            fix = true;
        } else if (std.mem.eql(u8, arg, "--verbose")) {
            verbose = true;
        } else if (std.mem.eql(u8, arg, "--cache")) {
            enable_cache = true;
        } else if (std.mem.eql(u8, arg, "--watch")) {
            enable_watch = true;
        } else if (std.mem.eql(u8, arg, "--json")) {
            json_output = true;
        } else if (std.mem.eql(u8, arg, "--list-rules")) {
            printRuleList(io);
            return;
        } else if (arg.len > 0 and arg[0] != '-') {
            try raw_paths.append(alloc, arg);
        } else {
            std.debug.print("unknown option: {s}\n", .{arg});
            std.process.exit(1);
        }
    }

    const paths = try expandPaths(raw_paths.items, io, alloc);
    defer {
        for (paths) |p| alloc.free(p);
        alloc.free(paths);
    }

    if (paths.len == 0) {
        try std.Io.File.stdout().writeStreamingAll(io, usage);
        return;
    }

    if (enable_watch) {
        var resolved_cfg_copy = readLinterConfig(config_path, io, alloc);
        defer resolved_cfg_copy.deinit(alloc);
        const lint_watcher = LintWatcher{
            .cfg = resolved_cfg_copy,
            .fix = fix,
            .config_path = config_path,
        };
        try watch.watchFiles(paths, LintWatcher, &lint_watcher, io, alloc);
        return;
    }

    var resolved_cfg = readLinterConfig(config_path, io, alloc);
    defer resolved_cfg.deinit(alloc);

    var cache_instance: ?cache.Cache = null;
    defer {
        if (cache_instance) |*c| c.deinit();
    }

    if (enable_cache) {
        const cache_path = try cache.defaultCachePath(io, alloc);
        defer alloc.free(cache_path);

        const config_hash = cache.computeConfigHash(resolved_cfg, alloc);

        cache_instance = cache.Cache.load(alloc, io, cache_path, config_hash) orelse
            cache.Cache.init(alloc, io, cache_path, config_hash);

        if (verbose) std.debug.print("[cache] using {s}\n", .{cache_path});
    }

    const project_root = cache.findProjectRoot(io, alloc);
    defer alloc.free(project_root);

    const start_time = nowMs();
    var had_errors = false;
    var fixed_count: usize = 0;
    var checked_count: usize = 0;
    for (paths) |path| {
        const file_start = nowMs();

        const rel = cache.normalizePath(path, project_root, alloc) catch {
            std.debug.print("error: failed to normalize path '{s}'\n", .{path});
            had_errors = true;
            continue;
        };

        if (cache_instance) |*c| {
            const stat = std.Io.Dir.cwd().statFile(io, path, .{}) catch |err| {
                std.debug.print("error: failed to stat '{s}': {}\n", .{ path, err });
                had_errors = true;
                alloc.free(rel);
                continue;
            };

            const mtime_ms = @as(f64, @floatFromInt(stat.mtime.nanoseconds)) / 1_000_000.0;

            if (!c.shouldLint(rel, mtime_ms, stat.size)) {
                if (verbose) std.debug.print("[cache] hit {s}\n", .{rel});
                if (c.getCachedDiagnostics(rel)) |diags| {
                    for (diags) |diag| {
                        if (json_output) {
                            printDiagnosticJson(diag);
                        } else {
                            printDiagnostic(diag);
                        }
                        if (diag.severity == .err) had_errors = true;
                    }
                }
                alloc.free(rel);
                continue;
            }

            if (verbose) std.debug.print("[cache] miss {s}\n", .{rel});
        }

        const lint_result = cli.lintPath(path, .{
            .fix = fix,
            .config_path = config_path,
            .config = resolved_cfg,
        }, io, alloc) catch |err| {
            std.debug.print("error: failed to lint '{s}': {}\n", .{ path, err });
            had_errors = true;
            alloc.free(rel);
            continue;
        };
        defer lint_result.result.deinit(alloc);

        const elapsed_ms = nowMs() - file_start;

        if (fix and lint_result.changed) {
            fixed_count += 1;
            if (verbose) std.debug.print("fixed {s} {d}ms\n", .{ path, elapsed_ms });
        } else {
            checked_count += 1;
            if (verbose) std.debug.print("checked {s} {d}ms\n", .{ path, elapsed_ms });

            for (lint_result.result.diagnostics) |diag| {
                if (json_output) {
                    printDiagnosticJson(diag);
                } else {
                    printDiagnostic(diag);
                }
                if (diag.severity == .err) had_errors = true;
            }
        }

        if (cache_instance) |*c| {
            const stat = std.Io.Dir.cwd().statFile(io, path, .{}) catch {
                alloc.free(rel);
                continue;
            };
            const mtime_ms = @as(f64, @floatFromInt(stat.mtime.nanoseconds)) / 1_000_000.0;
            c.update(rel, mtime_ms, stat.size, lint_result.result.diagnostics) catch |err| {
                std.debug.print("warning: failed to update cache: {}\n", .{err});
            };
        }

        alloc.free(rel);
    }

    if (cache_instance) |*c| {
        c.removeMissing(paths);
        c.save() catch |err| {
            std.debug.print("warning: failed to save cache: {}\n", .{err});
        };
        c.logStats();
    }

    const total_ms = nowMs() - start_time;
    if (fix) {
        if (fixed_count > 0) {
            std.debug.print("{d} file(s) formatted in {d}ms\n", .{ fixed_count, total_ms });
        } else if (checked_count > 0) {
            std.debug.print("No files changed\n", .{});
        } else {
            std.debug.print("No files changed\n", .{});
        }
    }
}

fn readLinterConfig(config_path: ?[]const u8, io: std.Io, alloc: std.mem.Allocator) linter.Config {
    if (config_path) |path| {
        return linter.readConfigFile(path, io, alloc) catch .{};
    }
    return linter.searchConfigCwd(io, alloc);
}

fn expandPaths(raw: []const []const u8, io: std.Io, alloc: std.mem.Allocator) ![][]const u8 {
    var result = std.ArrayListUnmanaged([]const u8).empty;
    errdefer {
        for (result.items) |p| alloc.free(p);
        result.deinit(alloc);
    }

    const entries = if (raw.len == 0) blk: {
        var single = try alloc.alloc([]const u8, 1);
        single[0] = ".";
        break :blk single;
    } else raw;

    for (entries) |entry| {
        switch (cli.classifyInputPath(entry, io)) {
            .file => try result.append(alloc, try alloc.dupe(u8, entry)),
            .directory => {
                const files = try cli.collectFiles(entry, io, alloc);
                for (files) |f| try result.append(alloc, f);
                alloc.free(files);
            },
            .missing => {
                std.debug.print("error: path not found: {s}\n", .{entry});
                std.process.exit(1);
            },
        }
    }

    if (raw.len == 0) alloc.free(entries);
    return result.toOwnedSlice(alloc);
}

fn printDiagnostic(diag: linter.Diagnostic) void {
    const sev = switch (diag.severity) {
        .off => "off",
        .err => "error",
        .warn => "warning",
        .info => "info",
    };
    const color_code = switch (diag.severity) {
        .err => "\x1b[31m",
        .warn => "\x1b[33m",
        .info => "\x1b[36m",
        .off => "",
    };
    const reset = "\x1b[0m";
    std.debug.print("{s}{s}{s}: {s}{s}:{d}:{d}{s}: {s}\n", .{
        color_code, sev, reset,
        reset, diag.filename, diag.range.start.line, diag.range.start.column, reset,
        diag.message,
    });
}

fn printDiagnosticJson(diag: linter.Diagnostic) void {
    const sev = switch (diag.severity) {
        .off => "off",
        .err => "error",
        .warn => "warning",
        .info => "info",
    };
    std.debug.print(
        \\{{"filename":"{s}","line":{d},"column":{d},"severity":"{s}","rule":"{s}","message":"{s}"}}
        \\
    , .{
        diag.filename,
        diag.range.start.line,
        diag.range.start.column,
        sev,
        diag.rule_code,
        diag.message,
    });
}

fn fatal(msg: []const u8) noreturn {
    std.debug.print("error: {s}\n", .{msg});
    std.process.exit(1);
}

fn printRuleList(io: std.Io) void {
    const rules = [_]struct { code: []const u8, sev: []const u8, desc: []const u8 }{
        .{ .code = "no-debugger", .sev = "err", .desc = "disallow debugger statements" },
        .{ .code = "no-alert", .sev = "err", .desc = "disallow alert, confirm, prompt" },
        .{ .code = "no-console", .sev = "warn", .desc = "disallow console.log and friends" },
        .{ .code = "no-eval", .sev = "err", .desc = "disallow eval()" },
        .{ .code = "no-globals", .sev = "err", .desc = "disallow assignment to global variables" },
        .{ .code = "no-new-native-nonconstructor", .sev = "err", .desc = "disallow new Symbol/new BigInt" },
        .{ .code = "no-process-exit", .sev = "err", .desc = "disallow process.exit()" },
        .{ .code = "no-iterator", .sev = "err", .desc = "disallow __iterator__ property" },
        .{ .code = "no-restricted-globals", .sev = "err", .desc = "disallow specified global variables" },
        .{ .code = "no-restricted-properties", .sev = "err", .desc = "disallow specified object properties" },
        .{ .code = "no-template-curly-in-string", .sev = "err", .desc = "disallow template literal placeholder in strings" },
        .{ .code = "no-self-compare", .sev = "err", .desc = "disallow comparisons where both sides are the same" },
        .{ .code = "no-constant-condition", .sev = "err", .desc = "disallow constant expressions in conditions" },
        .{ .code = "no-constant-binary-expression", .sev = "err", .desc = "disallow expressions that always evaluate to a constant" },
        .{ .code = "no-empty", .sev = "err", .desc = "disallow empty block statements" },
        .{ .code = "no-empty-character-class", .sev = "err", .desc = "disallow empty character classes in regex" },
        .{ .code = "no-extra-semi", .sev = "err", .desc = "disallow unnecessary semicolons" },
        .{ .code = "no-lone-blocks", .sev = "err", .desc = "disallow unnecessary nested blocks" },
        .{ .code = "no-unsafe-finally", .sev = "err", .desc = "disallow control flow in finally blocks" },
        .{ .code = "no-unused-vars", .sev = "warn", .desc = "disallow unused variables" },
        .{ .code = "no-var", .sev = "err", .desc = "require let or const" },
        .{ .code = "prefer-const", .sev = "warn", .desc = "require const for variables never reassigned" },
        .{ .code = "eqeqeq", .sev = "err", .desc = "require === and !==" },
        .{ .code = "no-dupe-keys", .sev = "err", .desc = "disallow duplicate keys in object literals" },
        .{ .code = "no-case-declarations", .sev = "err", .desc = "disallow lexical declarations in case blocks" },
        .{ .code = "no-async-promise-executor", .sev = "err", .desc = "disallow async Promise executor" },
        .{ .code = "no-inner-declarations", .sev = "err", .desc = "disallow function/var declarations in nested blocks" },
        .{ .code = "no-await-in-loop", .sev = "err", .desc = "disallow await inside loops" },
        .{ .code = "no-promise-executor-return", .sev = "err", .desc = "disallow return in Promise executor" },
        .{ .code = "preserve-caught-error", .sev = "err", .desc = "disallow overwriting caught error" },
        .{ .code = "prefer-template", .sev = "warn", .desc = "require template literals over string concat" },
        .{ .code = "no-constructor-return", .sev = "err", .desc = "disallow return value in class constructor" },
    };
    _ = io;
    std.debug.print("{d} rules available:\n\n", .{rules.len});
    for (rules) |r| {
        const sev_color = if (std.mem.eql(u8, r.sev, "err")) "error" else "warn";
        std.debug.print("  {s}  [{s}]  {s}\n", .{ r.code, sev_color, r.desc });
    }
}

const LintWatcher = struct {
    cfg: linter.Config,
    fix: bool,
    config_path: ?[]const u8,

    pub fn onChange(self: *const LintWatcher, path: []const u8, io: std.Io, alloc: std.mem.Allocator) !void {
        const result = cli.lintPath(path, .{
            .fix = self.fix,
            .config_path = self.config_path,
            .config = self.cfg,
        }, io, alloc) catch |err| {
            std.debug.print("  error linting {s}: {}\n", .{ path, err });
            return;
        };
        defer result.result.deinit(alloc);
        for (result.result.diagnostics) |diag| {
            printDiagnostic(diag);
        }
    }
};
