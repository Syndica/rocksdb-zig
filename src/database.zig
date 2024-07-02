const std = @import("std");
const rdb = @import("rocksdb");
const lib = @import("lib.zig");

const Allocator = std.mem.Allocator;

const RocksData = lib.RocksData;
const Iterator = lib.Iterator;
const RawIterator = lib.RawIterator;
const WriteBatch = lib.WriteBatch;

const copy = lib.data.copy;
const copyLen = lib.data.copyLen;

pub const Database = struct {
    allocator: Allocator,
    db: *rdb.rocksdb_t,
    column_families: std.StringHashMap(*rdb.rocksdb_column_family_handle_t),

    const Self = @This();

    pub fn open(dir: []const u8, err_str: *?RocksData) error{RocksDBOpen}!Self {
        const options = rdb.rocksdb_options_create();
        rdb.rocksdb_options_set_create_if_missing(options, 1); // TODO is null actually replaced?
        var ch = CallHandler.init(err_str);
        const db = try ch.handle(
            rdb.rocksdb_open(options, dir.ptr, &ch.err_str_in),
            error.RocksDBOpen,
        );
        return .{ .db = db.? };
    }

    pub fn openCf(
        allocator: Allocator,
        dir: []const u8,
        db_options: DBOptions,
        column_families: []const ColumnFamilyDescription,
        err_str: *?RocksData,
    ) (Allocator.Error || error{RocksDBOpen})!struct { Self, []const ColumnFamily } {
        const cf_options = try allocator.alloc(?*const rdb.rocksdb_options_t, column_families.len);
        defer allocator.free(cf_options);
        const cf_names = try allocator.alloc([*c]const u8, column_families.len);
        defer allocator.free(cf_names);
        for (column_families, 0..) |cf, i| {
            cf_names[i] = @ptrCast(cf.name.ptr);
            cf_options[i] = cf.options.convert();
        }
        const cf_handles = try allocator.alloc(?*rdb.rocksdb_column_family_handle_t, column_families.len);
        defer allocator.free(cf_handles);
        var ch = CallHandler.init(err_str);
        const db = try ch.handle(rdb.rocksdb_open_column_families(
            db_options.convert(),
            dir.ptr,
            @intCast(cf_names.len),
            @ptrCast(cf_names.ptr),
            @ptrCast(cf_options.ptr),
            @ptrCast(cf_handles.ptr),
            &ch.err_str_in,
        ), error.RocksDBOpen);
        const cfs = try allocator.alloc(ColumnFamily, column_families.len);
        var cf_map = std.StringHashMap(*rdb.rocksdb_column_family_handle_t).init(allocator);
        for (cfs, 0..) |*cf, i| {
            const name = try allocator.alloc(u8, column_families[i].name.len);
            @memcpy(name, column_families[i].name);
            cf.* = .{
                .name = name,
                .handle = cf_handles[i].?,
            };
            try cf_map.put(name, cf_handles[i].?);
        }
        const self = Self{
            .allocator = allocator,
            .db = db.?,
            .column_families = cf_map,
        };

        return .{ self, cfs };
    }

    pub fn deinit(self: *Self) void {
        var iter = self.column_families.keyIterator();
        while (iter.next()) |k| {
            self.allocator.free(k.*);
        }
        self.column_families.deinit();
        rdb.rocksdb_close(self.db);
    }

    pub fn createColumnFamily(
        self: *Self,
        name: []const u8,
        err_str: *?RocksData,
    ) !*rdb.rocksdb_column_family_handle_t {
        const options = rdb.rocksdb_options_create();
        var ch = CallHandler.init(err_str);
        return (try ch.handle(rdb.rocksdb_create_column_family(
            self.db,
            options,
            @as([*c]const u8, @ptrCast(name)),
            &ch.err_str_in,
        ), error.RocksDBCreateColumnFamily)).?;
    }

    pub fn columnFamily(self: *const Self, cf_name: []const u8) ?*rdb.rocksdb_column_family_handle_t {
        return self.column_families.get(cf_name);
    }

    pub fn put(
        self: *const Self,
        family: *rdb.rocksdb_column_family_handle_t,
        key: []const u8,
        value: []const u8,
        err_str: *?RocksData,
    ) error{RocksDBPut}!void {
        const options = rdb.rocksdb_writeoptions_create();
        defer rdb.rocksdb_writeoptions_destroy(options);
        var ch = CallHandler.init(err_str);
        try ch.handle(rdb.rocksdb_put_cf(
            self.db,
            options,
            family,
            key.ptr,
            key.len,
            value.ptr,
            value.len,
            &ch.err_str_in,
        ), error.RocksDBPut);
    }

    pub fn get(
        self: *const Self,
        family: *rdb.rocksdb_column_family_handle_t,
        key: []const u8,
        err_str: *?RocksData,
    ) error{RocksDBGet}!?RocksData {
        var valueLength: usize = 0;
        const options = rdb.rocksdb_readoptions_create();
        defer rdb.rocksdb_readoptions_destroy(options);
        var ch = CallHandler.init(err_str);
        const value = try ch.handle(rdb.rocksdb_get_cf(
            self.db,
            options,
            family,
            key.ptr,
            key.len,
            &valueLength,
            &ch.err_str_in,
        ), error.RocksDBGet);

        if (value == 0) {
            return null;
        }

        return .{ .data = value[0..valueLength] };
    }

    pub fn delete(
        self: *const Self,
        family: *rdb.rocksdb_column_family_handle_t,
        key: []const u8,
        err_str: *?RocksData,
    ) error{RocksDBDelete}!void {
        const options = rdb.rocksdb_writeoptions_create();
        defer rdb.rocksdb_writeoptions_destroy(options);
        var ch = CallHandler.init(err_str);
        try ch.handle(rdb.rocksdb_delete_cf(
            self.db,
            options,
            family,
            key.ptr,
            key.len,
            &ch.err_str_in,
        ), error.RocksDBDelete);
    }

    pub fn deleteFileInRange(
        self: *const Self,
        family: *rdb.rocksdb_column_family_handle_t,
        start_key: []const u8,
        limit_key: []const u8,
        err_str: *?RocksData,
    ) error{RocksDBDeleteFileInRange}!void {
        var ch = CallHandler.init(err_str);
        try ch.handle(rdb.rocksdb_delete_file_in_range_cf(
            self.db,
            family,
            @ptrCast(start_key.ptr),
            start_key.len,
            @ptrCast(limit_key.ptr),
            limit_key.len,
            &ch.err_str_in,
        ), error.RocksDBDeleteFileInRange);
    }

    pub fn iterator(
        self: *const Self,
        family: *rdb.rocksdb_column_family_handle_t,
    ) Iterator {
        const it = self.rawIterator(family);
        it.seekToFirst();
        return .{
            .raw = it,
            .direction = .forward,
            .done = false,
        };
    }

    pub fn rawIterator(
        self: *const Self,
        family: *rdb.rocksdb_column_family_handle_t,
    ) RawIterator {
        const options = rdb.rocksdb_readoptions_create();
        defer rdb.rocksdb_readoptions_destroy(options); // TODO does this need to outlive the iterator?
        const inner_iter = rdb.rocksdb_create_iterator_cf(self.db, options, family).?;
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
        family: *rdb.rocksdb_column_family_handle_t,
        propname: []const u8,
    ) RocksData {
        const value = rdb.rocksdb_property_value_cf(
            self.db,
            family,
            @ptrCast(propname.ptr),
        );
        return .{ .data = std.mem.span(value) };
    }

    pub fn write(
        self: *const Self,
        batch: WriteBatch,
        err_str: *?RocksData,
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
    handle: *rdb.rocksdb_column_family_handle_t,
};

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
    err_str_out: *?RocksData,

    fn init(err_str_out: *?RocksData) @This() {
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
            self.err_str_out.* = .{ .data = std.mem.span(s) };
            return err;
        } else {
            return ret;
        }
    }
};

test Database {
    var err_str: ?RocksData = null;
    defer if (err_str) |e| e.deinit();
    runTest(&err_str) catch |e| {
        std.debug.print("{}: {?}\n", .{ e, err_str });
        return e;
    };
}

fn runTest(err_str: *?RocksData) !void {
    var db, const families = try Database.openCf(
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
    const val = try db.get(a_family, "hello", err_str);
    try std.testing.expect(std.mem.eql(u8, val.?.data, "world"));

    var iter = db.iterator(a_family);
    var v = (try iter.nextValue(err_str)).?;
    try std.testing.expect(std.mem.eql(u8, "world", v.data));
    v = (try iter.nextValue(err_str)).?;
    try std.testing.expect(std.mem.eql(u8, "world", v.data));

    try std.testing.expect(null == try iter.next(err_str));

    try db.delete(a_family, "hello", err_str);

    const noval = try db.get(a_family, "hello", err_str);
    try std.testing.expect(null == noval);

    const lfs = try db.liveFiles(std.testing.allocator);
    defer lfs.deinit();
    defer for (lfs.items) |lf| lf.deinit();
    try std.testing.expect(std.mem.eql(u8, "another", lfs.items[0].column_family_name));
}
