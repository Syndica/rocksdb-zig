const std = @import("std");
const c = @import("rocksdb");

const path = "data";

pub fn main() !void {
    if (std.fs.cwd().access(path, .{})) |_| {
        try std.fs.cwd().deleteTree(path);
    } else |_| {}
    try std.fs.cwd().makePath(path);

    var cf_names: [1][*:0]const u8 = .{"default"};
    var cf_options: [1]*c.rocksdb_options_t = .{c.rocksdb_options_create().?};
    var cf_handles: [1]?*c.rocksdb_column_family_handle_t = undefined;

    const db = db: {
        const db_options = c.rocksdb_options_create().?;
        c.rocksdb_options_set_create_if_missing(db_options, 1);
        var errptr: ?*[1024]u8 = null;
        const maybe_db = c.rocksdb_open_column_families(
            db_options,
            "data".ptr,
            1,
            @ptrCast(&cf_names),
            @ptrCast(&cf_options),
            @ptrCast(&cf_handles),
            @ptrCast(&errptr),
        );
        if (errptr) |e| std.debug.print("error: {s}", .{e});
        break :db maybe_db.?;
    };

    const delete_start = [_]u8{182};
    const delete_end = [_]u8{190};
    const get = [_]u8{61};

    const batch = c.rocksdb_writebatch_create().?;
    c.rocksdb_writebatch_delete_range_cf(
        batch,
        cf_handles[0],
        (&delete_start).ptr,
        (&delete_start).len,
        (&delete_end).ptr,
        (&delete_end).len,
    );

    {
        // var raw_err_str: [1024]u8 = undefined;
        var errptr: ?*[1024]u8 = null;
        defer if (errptr) |e| std.debug.print("error: {s}", .{e});
        const options = c.rocksdb_writeoptions_create();
        c.rocksdb_write(db, options, batch, @ptrCast(&errptr));
    }

    {
        // var raw_err_str: [1024]u8 = undefined;
        var errptr: ?*[1024]u8 = null;
        defer if (errptr) |e| std.debug.print("error: {s}", .{e});
        const read_options = c.rocksdb_readoptions_create();
        var vallen: usize = 0;
        _ = c.rocksdb_get_cf(
            db,
            read_options,
            cf_handles[0],
            @ptrCast(&get),
            get.len,
            @ptrCast(&vallen),
            @ptrCast(&errptr),
        );
    }

    std.debug.print("it works", .{});
}
