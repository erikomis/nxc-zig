const std = @import("std");

pub const CacheEntry = struct {
    source_hash: u64,
    deps: []const u8,
    dep_hashes: []const u64,
    output_hash: u64,
    last_modified: i128,
    source_path: []const u8,

    pub fn deinit(entry: *CacheEntry, alloc: std.mem.Allocator) void {
        alloc.free(entry.source_path);
        alloc.free(entry.deps);
        alloc.free(entry.dep_hashes);
    }
};

pub const CacheStore = struct {
    entries: std.StringHashMapUnmanaged(CacheEntry),
    cache_dir: []const u8,

    pub fn init(cache_dir: []const u8) CacheStore {
        return .{
            .entries = .{},
            .cache_dir = cache_dir,
        };
    }

    pub fn deinit(self: *CacheStore, alloc: std.mem.Allocator) void {
        var it = self.entries.iterator();
        while (it.next()) |entry| {
            alloc.free(entry.key_ptr.*);
            entry.value_ptr.deinit(alloc);
        }
        self.entries.deinit(alloc);
    }

    pub fn get(self: *CacheStore, path: []const u8) ?CacheEntry {
        return self.entries.get(path);
    }

    pub fn put(self: *CacheStore, alloc: std.mem.Allocator, path: []const u8, entry: CacheEntry) !void {
        const gop = try self.entries.getOrPut(alloc, path);
        if (gop.found_existing) {
            alloc.free(gop.key_ptr.*);
            gop.value_ptr.deinit(alloc);
        }
        gop.key_ptr.* = try alloc.dupe(u8, path);
        gop.value_ptr.* = entry;
    }

    pub fn isStale(self: *CacheStore, path: []const u8, current_hash: u64) bool {
        const entry = self.entries.get(path) orelse return true;
        return entry.source_hash != current_hash;
    }

    fn crc32Checksum(data: []const u8) u32 {
        var crc = std.hash.Crc32.init();
        crc.update(data);
        return crc.final();
    }

    pub fn save(self: *CacheStore, io: std.Io, alloc: std.mem.Allocator) !void {
        const cache_path = try std.fs.path.join(alloc, &.{ self.cache_dir, "cache.txt" });
        defer alloc.free(cache_path);

        std.Io.Dir.cwd().createDirPath(io, self.cache_dir) catch |err| {
            std.log.warn("cache: failed to create cache dir: {}", .{err});
        };

        var lines = std.ArrayList(u8).init(alloc);
        defer lines.deinit();

        const writer = lines.writer();

        var it = self.entries.iterator();
        while (it.next()) |entry| {
            try writer.print("{s}|{d}|{s}|", .{
                entry.key_ptr.*,
                entry.value_ptr.source_hash,
                entry.value_ptr.deps,
            });

            for (entry.value_ptr.dep_hashes, 0..) |hash, i| {
                if (i > 0) try writer.writeAll(",");
                try writer.print("{d}", .{hash});
            }

            try writer.print("|{d}|{d}|{s}\n", .{
                entry.value_ptr.output_hash,
                entry.value_ptr.last_modified,
                entry.value_ptr.source_path,
            });
        }

        const file = try std.Io.Dir.cwd().createFile(io, cache_path, .{ .truncate = true });
        defer file.close(io);

        const header = try std.fmt.allocPrint(alloc, "nxcache|{d}|\n", .{crc32Checksum(lines.items)});
        defer alloc.free(header);
        try file.writeStreamingAll(io, header);
        try file.writeStreamingAll(io, lines.items);
    }

    pub fn load(self: *CacheStore, io: std.Io, alloc: std.mem.Allocator) !void {
        {
            var it = self.entries.iterator();
            while (it.next()) |entry| {
                alloc.free(entry.key_ptr.*);
                entry.value_ptr.deinit(alloc);
            }
        }
        self.entries.clear();

        const cache_path = std.fs.path.join(alloc, &.{ self.cache_dir, "cache.txt" }) catch return;
        defer alloc.free(cache_path);

        const content = std.Io.Dir.cwd().readFileAlloc(io, cache_path, alloc, std.Io.Limit.limited(10 * 1024 * 1024)) catch |err| switch (err) {
            error.FileNotFound => return,
            else => return,
        };
        defer alloc.free(content);

        // Validate header
        var lines = std.mem.splitScalar(u8, content, '\n');
        const header_line = lines.next() orelse return;
        if (!std.mem.startsWith(u8, header_line, "nxcache|")) return;
        var header_parts = std.mem.splitScalar(u8, header_line, '|');
        _ = header_parts.next(); // "nxcache"
        const stored_checksum = std.fmt.parseInt(u32, header_parts.next() orelse return, 10) catch return;

        const data_start = header_line.len + 1; // +1 for the newline
        if (data_start >= content.len) return;
        const payload = content[data_start..];
        const actual_checksum = crc32Checksum(payload);
        if (actual_checksum != stored_checksum) return;

        while (lines.next()) |line| {
            if (line.len == 0) continue;

            var parts = std.mem.splitScalar(u8, line, '|');
            const path = parts.next() orelse continue;
            const source_hash = std.fmt.parseInt(u64, parts.next() orelse continue, 10) catch continue;
            const deps = parts.next() orelse continue;
            const dep_hashes_str = parts.next() orelse continue;
            const output_hash = std.fmt.parseInt(u64, parts.next() orelse continue, 10) catch continue;
            const last_modified = std.fmt.parseInt(i128, parts.next() orelse continue, 10) catch continue;
            const source_path = parts.rest();

            var dep_hashes_list = std.ArrayList(u64).init(alloc);
            defer dep_hashes_list.deinit();

            if (dep_hashes_str.len > 0) {
                var hash_parts = std.mem.splitScalar(u8, dep_hashes_str, ',');
                while (hash_parts.next()) |hp| {
                    if (hp.len == 0) continue;
                    dep_hashes_list.append(std.fmt.parseInt(u64, hp, 10) catch continue) catch continue;
                }
            }

            const entry = CacheEntry{
                .source_hash = source_hash,
                .deps = try alloc.dupe(u8, deps),
                .dep_hashes = try dep_hashes_list.toOwnedSlice(alloc),
                .output_hash = output_hash,
                .last_modified = last_modified,
                .source_path = try alloc.dupe(u8, source_path),
            };

            const key = try alloc.dupe(u8, path);
            self.entries.put(alloc, key, entry) catch {
                alloc.free(key);
                entry.deinit(alloc);
            };
        }
    }

    pub fn clear(self: *CacheStore) void {
        self.entries.clear();
    }
};

pub const IncrementalInfo = struct {
    store: CacheStore,
    dirty_files: std.ArrayListUnmanaged([]const u8) = .empty,
    clean_files: std.ArrayListUnmanaged([]const u8) = .empty,

    pub fn checkFiles(self: *IncrementalInfo, files: []const []const u8, io: std.Io, alloc: std.mem.Allocator) !void {
        self.dirty_files.clearRetainingCapacity();
        self.clean_files.clearRetainingCapacity();

        for (files) |file| {
            const content = std.Io.Dir.cwd().readFileAlloc(io, file, alloc, std.Io.Limit.limited(64 * 1024 * 1024)) catch {
                try self.dirty_files.append(alloc, file);
                continue;
            };
            defer alloc.free(content);

            var hasher = std.hash.Wyhash.init(0);
            hasher.update(content);
            const hash = hasher.final();

            if (self.store.isStale(file, hash)) {
                try self.dirty_files.append(alloc, file);
            } else {
                try self.clean_files.append(alloc, file);
            }
        }
    }

    pub fn markDirty(self: *IncrementalInfo, path: []const u8, alloc: std.mem.Allocator) !void {
        try self.dirty_files.append(alloc, path);
    }

    pub fn markClean(self: *IncrementalInfo, path: []const u8, alloc: std.mem.Allocator) !void {
        try self.clean_files.append(alloc, path);
    }
};

pub fn hashBytes(bytes: []const u8) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(bytes);
    return hasher.final();
}

pub fn hashFile(path: []const u8, io: std.Io, alloc: std.mem.Allocator) !u64 {
    const content = try std.Io.Dir.cwd().readFileAlloc(io, path, alloc, std.Io.Limit.limited(64 * 1024 * 1024));
    defer alloc.free(content);
    return hashBytes(content);
}
