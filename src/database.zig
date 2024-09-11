const std = @import("std");
const rdb = @import("rocksdb");
const lib = @import("lib.zig");

const Allocator = std.mem.Allocator;
const RwLock = std.Thread.RwLock;

const Data = lib.Data;
const Iterator = lib.Iterator;
const IteratorDirection = lib.IteratorDirection;
const RawIterator = lib.RawIterator;
const WriteBatch = lib.WriteBatch;

const copy = lib.data.copy;
const copyLen = lib.data.copyLen;

const general_freer = lib.data.general_freer;

pub const DB = struct {
    db: *rdb.rocksdb_t,
    default_cf: ?ColumnFamilyHandle = null,
    cf_name_to_handle: *CfNameToHandleMap,

    const Self = @This();

    pub fn open(
        allocator: Allocator,
        dir: []const u8,
        db_options: DBOptions,
        maybe_column_families: ?[]const ColumnFamilyDescription,
        err_str: *?Data,
    ) (Allocator.Error || error{RocksDBOpen})!struct { Self, []const ColumnFamily } {
        const column_families = if (maybe_column_families) |cfs|
            cfs
        else
            &[1]ColumnFamilyDescription{.{ .name = "default" }};

        const cf_handles = try allocator.alloc(?ColumnFamilyHandle, column_families.len);
        defer allocator.free(cf_handles);

        // open database
        const db = db: {
            const cf_options = try allocator.alloc(?*const rdb.rocksdb_options_t, column_families.len);
            defer allocator.free(cf_options);
            const cf_names = try allocator.alloc([*c]const u8, column_families.len);
            defer allocator.free(cf_names);
            for (column_families, 0..) |cf, i| {
                cf_names[i] = @ptrCast(cf.name.ptr);
                cf_options[i] = cf.options.convert();
            }
            var ch = CallHandler.init(err_str);
            break :db try ch.handle(rdb.rocksdb_open_column_families(
                db_options.convert(),
                dir.ptr,
                @intCast(cf_names.len),
                @ptrCast(cf_names.ptr),
                @ptrCast(cf_options.ptr),
                @ptrCast(cf_handles.ptr),
                &ch.err_str_in,
            ), error.RocksDBOpen);
        };

        // organize column family metadata
        const cf_list = try allocator.alloc(ColumnFamily, column_families.len);
        errdefer allocator.free(cf_list);
        const cf_map = try CfNameToHandleMap.create(allocator);
        errdefer cf_map.destroy();
        for (cf_list, 0..) |*cf, i| {
            const name = try allocator.dupe(u8, column_families[i].name);
            cf.* = .{
                .name = name,
                .handle = cf_handles[i].?,
            };
            try cf_map.map.put(allocator, name, cf_handles[i].?);
        }

        return .{
            Self{ .db = db.?, .cf_name_to_handle = cf_map },
            cf_list,
        };
    }

    pub fn withDefaultColumnFamily(self: Self, column_family: ColumnFamilyHandle) Self {
        return .{
            .db = self.db,
            .cf_name_to_handle = self.cf_name_to_handle,
            .default_cf = column_family,
        };
    }

    /// Closes the database and cleans up this struct's state.
    pub fn deinit(self: Self) void {
        self.cf_name_to_handle.destroy();
        rdb.rocksdb_close(self.db);
    }

    /// Delete the entire database from the filesystem.
    /// Destroying a database after it is closed has undefined behavior.
    pub fn destroy(self: Self) error{Closed}!void {
        rdb.rocksdb_destroy_db(self.db);
    }

    pub fn createColumnFamily(
        self: *Self,
        name: []const u8,
        err_str: *?Data,
    ) !ColumnFamilyHandle {
        const options = rdb.rocksdb_options_create();
        var ch = CallHandler.init(err_str);
        const handle = (try ch.handle(rdb.rocksdb_create_column_family(
            self.db,
            options,
            @as([*c]const u8, @ptrCast(name)),
            &ch.err_str_in,
        ), error.RocksDBCreateColumnFamily)).?;
        self.cf_name_to_handle.put(name, handle);
        return handle;
    }

    pub fn columnFamily(
        self: *const Self,
        cf_name: []const u8,
    ) error{UnknownColumnFamily}!ColumnFamilyHandle {
        return self.cf_name_to_handle.get(cf_name) orelse error.UnknownColumnFamily;
    }

    pub fn put(
        self: *const Self,
        column_family: ?ColumnFamilyHandle,
        key: []const u8,
        value: []const u8,
        err_str: *?Data,
    ) error{RocksDBPut}!void {
        const options = rdb.rocksdb_writeoptions_create();
        defer rdb.rocksdb_writeoptions_destroy(options);
        var ch = CallHandler.init(err_str);
        try ch.handle(rdb.rocksdb_put_cf(
            self.db,
            options,
            column_family orelse self.default_cf,
            key.ptr,
            key.len,
            value.ptr,
            value.len,
            &ch.err_str_in,
        ), error.RocksDBPut);
    }

    pub fn get(
        self: *const Self,
        column_family: ?ColumnFamilyHandle,
        key: []const u8,
        err_str: *?Data,
    ) error{RocksDBGet}!?Data {
        var valueLength: usize = 0;
        const options = rdb.rocksdb_readoptions_create();
        defer rdb.rocksdb_readoptions_destroy(options);
        var ch = CallHandler.init(err_str);
        const value = try ch.handle(rdb.rocksdb_get_cf(
            self.db,
            options,
            column_family orelse self.default_cf,
            key.ptr,
            key.len,
            &valueLength,
            &ch.err_str_in,
        ), error.RocksDBGet);
        if (value == 0) {
            return null;
        }
        return .{
            .allocator = general_freer,
            .data = value[0..valueLength],
        };
    }

    pub fn delete(
        self: *const Self,
        column_family: ?ColumnFamilyHandle,
        key: []const u8,
        err_str: *?Data,
    ) error{RocksDBDelete}!void {
        const options = rdb.rocksdb_writeoptions_create();
        defer rdb.rocksdb_writeoptions_destroy(options);
        var ch = CallHandler.init(err_str);
        try ch.handle(rdb.rocksdb_delete_cf(
            self.db,
            options,
            column_family orelse self.default_cf,
            key.ptr,
            key.len,
            &ch.err_str_in,
        ), error.RocksDBDelete);
    }

    pub fn deleteFilesInRange(
        self: *const Self,
        column_family: ?ColumnFamilyHandle,
        start_key: []const u8,
        limit_key: []const u8,
        err_str: *?Data,
    ) error{RocksDBDeleteFilesInRange}!void {
        var ch = CallHandler.init(err_str);
        try ch.handle(rdb.rocksdb_delete_file_in_range_cf(
            self.db,
            column_family orelse self.default_cf,
            @ptrCast(start_key.ptr),
            start_key.len,
            @ptrCast(limit_key.ptr),
            limit_key.len,
            &ch.err_str_in,
        ), error.RocksDBDeleteFilesInRange);
    }

    pub fn iterator(
        self: *const Self,
        column_family: ?ColumnFamilyHandle,
        direction: IteratorDirection,
        start: ?[]const u8,
    ) Iterator {
        const it = self.rawIterator(column_family);
        if (start) |seek_target| switch (direction) {
            .forward => it.seek(seek_target),
            .reverse => it.seekForPrev(seek_target),
        } else switch (direction) {
            .forward => it.seekToFirst(),
            .reverse => it.seekToLast(),
        }
        return .{
            .raw = it,
            .direction = direction,
            .done = false,
        };
    }

    pub fn rawIterator(
        self: *const Self,
        column_family: ?ColumnFamilyHandle,
    ) RawIterator {
        const options = rdb.rocksdb_readoptions_create();
        defer rdb.rocksdb_readoptions_destroy(options); // TODO does this need to outlive the iterator?
        const inner_iter = rdb.rocksdb_create_iterator_cf(
            self.db,
            options,
            column_family orelse self.default_cf,
        ).?;
        const ri = RawIterator{ .inner = inner_iter };
        return ri;
    }

    pub fn liveFiles(self: *const Self, allocator: Allocator) Allocator.Error!std.ArrayList(LiveFile) {
        const files = rdb.rocksdb_livefiles(self.db).?;
        const num_files: usize = @intCast(rdb.rocksdb_livefiles_count(files));
        var livefiles = std.ArrayList(LiveFile).init(allocator);
        var key_size: usize = 0;
        for (0..num_files) |i| {
            const file_num: c_int = @intCast(i);
            try livefiles.append(.{
                .allocator = allocator,
                .column_family_name = try copy(allocator, rdb.rocksdb_livefiles_column_family_name(files, file_num)),
                .name = try copy(allocator, rdb.rocksdb_livefiles_name(files, file_num)),
                .size = rdb.rocksdb_livefiles_size(files, file_num),
                .level = rdb.rocksdb_livefiles_level(files, file_num),
                .start_key = try copyLen(allocator, rdb.rocksdb_livefiles_smallestkey(files, file_num, &key_size), key_size),
                .end_key = try copyLen(allocator, rdb.rocksdb_livefiles_largestkey(files, file_num, &key_size), key_size),
                .num_entries = rdb.rocksdb_livefiles_entries(files, file_num),
                .num_deletions = rdb.rocksdb_livefiles_deletions(files, file_num),
            });
        }
        rdb.rocksdb_livefiles_destroy(files);
        return livefiles;
    }

    pub fn propertyValueCf(
        self: *const Self,
        column_family: ?ColumnFamilyHandle,
        propname: []const u8,
    ) Data {
        const value = rdb.rocksdb_property_value_cf(
            self.db,
            column_family orelse self.default_cf,
            @ptrCast(propname.ptr),
        );
        return .{
            .data = std.mem.span(value),
            .allocator = general_freer,
        };
    }

    pub fn write(
        self: *const Self,
        batch: WriteBatch,
        err_str: *?Data,
    ) error{RocksDBWrite}!void {
        const options = rdb.rocksdb_writeoptions_create();
        defer rdb.rocksdb_writeoptions_destroy(options);
        var ch = CallHandler.init(err_str);
        try ch.handle(rdb.rocksdb_write(
            self.db,
            options,
            batch.inner,
            &ch.err_str_in,
        ), error.RocksDBWrite);
    }
};

pub const DBOptions = struct {
    create_if_missing: bool = false,
    create_missing_column_families: bool = false,

    fn convert(do: DBOptions) *rdb.struct_rocksdb_options_t {
        const ro = rdb.rocksdb_options_create().?;
        if (do.create_if_missing) rdb.rocksdb_options_set_create_if_missing(ro, 1);
        if (do.create_missing_column_families) rdb.rocksdb_options_set_create_missing_column_families(ro, 1);
        return ro;
    }
};

pub const ColumnFamilyDescription = struct {
    name: []const u8,
    options: ColumnFamilyOptions = .{},
};

pub const ColumnFamily = struct {
    name: []const u8,
    handle: ColumnFamilyHandle,
};

pub const ColumnFamilyHandle = *rdb.rocksdb_column_family_handle_t;

pub const ColumnFamilyOptions = struct {
    fn convert(_: ColumnFamilyOptions) *rdb.struct_rocksdb_options_t {
        return rdb.rocksdb_options_create().?;
    }
};

/// The metadata that describes a SST file
pub const LiveFile = struct {
    allocator: Allocator,
    /// Name of the column family the file belongs to
    column_family_name: []const u8,
    /// Name of the file
    name: []const u8,
    /// Size of the file
    size: usize,
    /// Level at which this file resides
    level: i32,
    /// Smallest user defined key in the file
    start_key: ?[]const u8,
    /// Largest user defined key in the file
    end_key: ?[]const u8,
    /// Number of entries/alive keys in the file
    num_entries: u64,
    /// Number of deletions/tomb key(s) in the file
    num_deletions: u64,

    pub fn deinit(self: LiveFile) void {
        self.allocator.free(self.column_family_name);
        self.allocator.free(self.name);
        if (self.start_key) |start_key| self.allocator.free(start_key);
        if (self.end_key) |end_key| self.allocator.free(end_key);
    }
};

const CallHandler = struct {
    /// The error string to pass into rocksdb.
    err_str_in: ?[*:0]u8 = null,
    /// The user's error string.
    err_str_out: *?Data,

    fn init(err_str_out: *?Data) @This() {
        return .{ .err_str_out = err_str_out };
    }

    fn errIn(self: *@This()) [*c][*c]u8 {
        return @ptrCast(&self.err_str_in);
    }

    fn handle(
        self: *@This(),
        ret: anytype,
        comptime err: anytype,
    ) @TypeOf(err)!@TypeOf(ret) {
        if (self.err_str_in) |s| {
            self.err_str_out.* = .{
                .data = std.mem.span(s),
                .allocator = general_freer,
            };
            return err;
        } else {
            return ret;
        }
    }
};

const CfNameToHandleMap = struct {
    allocator: Allocator,
    map: std.StringHashMapUnmanaged(ColumnFamilyHandle),
    lock: RwLock,

    const Self = @This();

    fn create(allocator: Allocator) Allocator.Error!*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .map = .{},
            .lock = .{},
        };
        return self;
    }

    fn destroy(self: *Self) void {
        var iter = self.map.iterator();
        while (iter.next()) |entry| {
            rdb.rocksdb_column_family_handle_destroy(entry.value_ptr.*);
            self.allocator.free(entry.key_ptr.*);
        }
        self.map.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    fn put(self: *Self, name: []const u8, handle: ColumnFamilyHandle) Allocator.Error!void {
        const owned_name = try self.allocator.dupe(u8, name);

        self.lock.lock();
        defer self.lock.unlock();

        self.map.put(self.allocator, owned_name, handle);
    }

    fn get(self: *const Self, name: []const u8) ?ColumnFamilyHandle {
        self.lock.lockShared();
        defer self.lock.unlockShared();
        return self.map.get(name);
    }
};

test DB {
    var err_str: ?Data = null;
    defer if (err_str) |e| e.deinit();
    runTest(&err_str) catch |e| {
        std.debug.print("{}: {?}\n", .{ e, err_str });
        return e;
    };
}

fn runTest(err_str: *?Data) !void {
    var db, const families = try DB.open(
        std.testing.allocator,
        "test-state",
        .{
            .create_if_missing = true,
            .create_missing_column_families = true,
        },
        &.{
            .{ .name = "default" },
            .{ .name = "another" },
        },
        err_str,
    );
    defer db.deinit();
    defer std.testing.allocator.free(families);
    const a_family = families[1].handle;

    _ = try db.put(a_family, "hello", "world", err_str);
    _ = try db.put(a_family, "zebra", "world", err_str);

    db = db.withDefaultColumnFamily(a_family);

    const val = try db.get(null, "hello", err_str);
    try std.testing.expect(std.mem.eql(u8, val.?.data, "world"));

    var iter = db.iterator(null, .forward, null);
    defer iter.deinit();
    var v = (try iter.nextValue(err_str)).?;
    try std.testing.expect(std.mem.eql(u8, "world", v.data));
    v = (try iter.nextValue(err_str)).?;
    try std.testing.expect(std.mem.eql(u8, "world", v.data));
    try std.testing.expect(null == try iter.next(err_str));

    try db.delete(null, "hello", err_str);

    const noval = try db.get(null, "hello", err_str);
    try std.testing.expect(null == noval);

    const lfs = try db.liveFiles(std.testing.allocator);
    defer lfs.deinit();
    defer for (lfs.items) |lf| lf.deinit();
    try std.testing.expect(std.mem.eql(u8, "another", lfs.items[0].column_family_name));
}
