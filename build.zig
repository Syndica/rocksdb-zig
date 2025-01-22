const std = @import("std");
const Build = std.Build;
const ResolvedTarget = Build.ResolvedTarget;
const OptimizeMode = std.builtin.OptimizeMode;

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // rocksdb itself as a zig module
    const rocksdb_mod = addRocksDB(b, target, optimize);

    const exe = b.addExecutable(.{
        .name = "rocksdb_segfault",
        .root_source_file = b.path("c-repro.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("rocksdb", rocksdb_mod);
    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

/// Create a zig module for the bare C++ library by exposing its C api.
/// Builds rocksdb, links it, and translates its headers.
fn addRocksDB(
    b: *Build,
    target: ResolvedTarget,
    optimize: OptimizeMode,
) *Build.Module {
    const rocks_dep = b.dependency("rocksdb", .{});

    const translate_c = b.addTranslateC(.{
        .root_source_file = rocks_dep.path("include/rocksdb/c.h"),
        .target = target,
        .optimize = optimize,
    });
    const mod = b.addModule("rocksdb", .{
        .root_source_file = translate_c.getOutput(),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
    });

    const librocksdb_a = b.addStaticLibrary(.{
        .name = "rocksdb",
        .target = target,
        .optimize = optimize,
    });
<<<<<<< Updated upstream
    const librocksdb_so = b.addSharedLibrary(.{
        .name = "rocksdb",
        .target = target,
        .optimize = optimize,
    });

    try buildRocksDB(b, librocksdb_a, target);
    try buildRocksDB(b, librocksdb_so, target);

    mod.addIncludePath(rocks_dep.path("include"));
    mod.linkLibrary(librocksdb_a);
=======
    const rocks_path = rocks_dep.path("");

    const librocksdb_a = addMakeAndMove(b, make_and_move, rocks_path, "static_lib", "librocksdb.a");
    const libbz2_a = addMakeAndMove(b, make_and_move, rocks_path, "libbz2.a", "libbz2.a");
    const libz_a = addMakeAndMove(b, make_and_move, rocks_path, "libz.a", "libz.a");
    const libzstd_a = addMakeAndMove(b, make_and_move, rocks_path, "libzstd.a", "libzstd.a");
    const libsnappy_a = addMakeAndMove(b, make_and_move, rocks_path, "libsnappy.a", "libsnappy.a");
    const liblz4_a = addMakeAndMove(b, make_and_move, rocks_path, "liblz4.a", "liblz4.a");

    mod.addIncludePath(rocks_dep.path("include"));

    mod.addObjectFile(librocksdb_a);
    mod.addObjectFile(libbz2_a);
    mod.addObjectFile(libz_a);
    mod.addObjectFile(libzstd_a);
    mod.addObjectFile(libsnappy_a);
    mod.addObjectFile(liblz4_a);
    mod.addObjectFile(.{ .cwd_relative = "/usr/lib/libstdc++.a" });

    // mod.linkSystemLibrary("", options: LinkSystemLibraryOptions)
>>>>>>> Stashed changes

    return mod;
}

/// The build process for rocksdb itself. works for static or shared library
fn buildRocksDB(
    b: *Build,
    librocksdb: *std.Build.Step.Compile,
    target: std.Build.ResolvedTarget,
) !void {
    const t = target.result;
    const rocks_dep = b.dependency("rocksdb", .{});

    librocksdb.linkLibC();
    librocksdb.linkLibCpp();

    librocksdb.addIncludePath(rocks_dep.path("include"));
    librocksdb.addIncludePath(rocks_dep.path("."));
    librocksdb.addCSourceFiles(.{
        .root = rocks_dep.path("."),
        .files = &.{
            "cache/cache.cc",
            "cache/cache_entry_roles.cc",
            "cache/cache_key.cc",
            "cache/cache_helpers.cc",
            "cache/cache_reservation_manager.cc",
            "cache/charged_cache.cc",
            "cache/clock_cache.cc",
            "cache/compressed_secondary_cache.cc",
            "cache/lru_cache.cc",
            "cache/secondary_cache.cc",
            "cache/secondary_cache_adapter.cc",
            "cache/sharded_cache.cc",
            "cache/tiered_secondary_cache.cc",
            "db/arena_wrapped_db_iter.cc",
            "db/attribute_group_iterator_impl.cc",
            "db/blob/blob_contents.cc",
            "db/blob/blob_fetcher.cc",
            "db/blob/blob_file_addition.cc",
            "db/blob/blob_file_builder.cc",
            "db/blob/blob_file_cache.cc",
            "db/blob/blob_file_garbage.cc",
            "db/blob/blob_file_meta.cc",
            "db/blob/blob_file_reader.cc",
            "db/blob/blob_garbage_meter.cc",
            "db/blob/blob_log_format.cc",
            "db/blob/blob_log_sequential_reader.cc",
            "db/blob/blob_log_writer.cc",
            "db/blob/blob_source.cc",
            "db/blob/prefetch_buffer_collection.cc",
            "db/builder.cc",
            "db/c.cc",
            "db/coalescing_iterator.cc",
            "db/column_family.cc",
            "db/compaction/compaction.cc",
            "db/compaction/compaction_iterator.cc",
            "db/compaction/compaction_picker.cc",
            "db/compaction/compaction_job.cc",
            "db/compaction/compaction_picker_fifo.cc",
            "db/compaction/compaction_picker_level.cc",
            "db/compaction/compaction_picker_universal.cc",
            "db/compaction/compaction_service_job.cc",
            "db/compaction/compaction_state.cc",
            "db/compaction/compaction_outputs.cc",
            "db/compaction/sst_partitioner.cc",
            "db/compaction/subcompaction_state.cc",
            "db/convenience.cc",
            "db/db_filesnapshot.cc",
            "db/db_impl/compacted_db_impl.cc",
            "db/db_impl/db_impl.cc",
            "db/db_impl/db_impl_write.cc",
            "db/db_impl/db_impl_compaction_flush.cc",
            "db/db_impl/db_impl_files.cc",
            "db/db_impl/db_impl_follower.cc",
            "db/db_impl/db_impl_open.cc",
            "db/db_impl/db_impl_debug.cc",
            "db/db_impl/db_impl_experimental.cc",
            "db/db_impl/db_impl_readonly.cc",
            "db/db_impl/db_impl_secondary.cc",
            "db/db_info_dumper.cc",
            "db/db_iter.cc",
            "db/dbformat.cc",
            "db/error_handler.cc",
            "db/event_helpers.cc",
            "db/experimental.cc",
            "db/external_sst_file_ingestion_job.cc",
            "db/file_indexer.cc",
            "db/flush_job.cc",
            "db/flush_scheduler.cc",
            "db/forward_iterator.cc",
            "db/import_column_family_job.cc",
            "db/internal_stats.cc",
            "db/logs_with_prep_tracker.cc",
            "db/log_reader.cc",
            "db/log_writer.cc",
            "db/malloc_stats.cc",
            "db/memtable.cc",
            "db/memtable_list.cc",
            "db/merge_helper.cc",
            "db/merge_operator.cc",
            "db/output_validator.cc",
            "db/periodic_task_scheduler.cc",
            "db/range_del_aggregator.cc",
            "db/range_tombstone_fragmenter.cc",
            "db/repair.cc",
            "db/seqno_to_time_mapping.cc",
            "db/snapshot_impl.cc",
            "db/table_cache.cc",
            "db/table_properties_collector.cc",
            "db/transaction_log_impl.cc",
            "db/trim_history_scheduler.cc",
            "db/version_builder.cc",
            "db/version_edit.cc",
            "db/version_edit_handler.cc",
            "db/version_set.cc",
            "db/wal_edit.cc",
            "db/wal_manager.cc",
            "db/wide/wide_column_serialization.cc",
            "db/wide/wide_columns.cc",
            "db/wide/wide_columns_helper.cc",
            "db/write_batch.cc",
            "db/write_batch_base.cc",
            "db/write_controller.cc",
            "db/write_stall_stats.cc",
            "db/write_thread.cc",
            "env/composite_env.cc",
            "env/env.cc",
            "env/env_chroot.cc",
            "env/env_encryption.cc",
            "env/file_system.cc",
            "env/file_system_tracer.cc",
            "env/fs_on_demand.cc",
            "env/fs_remap.cc",
            "env/mock_env.cc",
            "env/unique_id_gen.cc",
            "file/delete_scheduler.cc",
            "file/file_prefetch_buffer.cc",
            "file/file_util.cc",
            "file/filename.cc",
            "file/line_file_reader.cc",
            "file/random_access_file_reader.cc",
            "file/read_write_util.cc",
            "file/readahead_raf.cc",
            "file/sequence_file_reader.cc",
            "file/sst_file_manager_impl.cc",
            "file/writable_file_writer.cc",
            "logging/auto_roll_logger.cc",
            "logging/event_logger.cc",
            "logging/log_buffer.cc",
            "memory/arena.cc",
            "memory/concurrent_arena.cc",
            "memory/jemalloc_nodump_allocator.cc",
            "memory/memkind_kmem_allocator.cc",
            "memory/memory_allocator.cc",
            "memtable/alloc_tracker.cc",
            "memtable/hash_linklist_rep.cc",
            "memtable/hash_skiplist_rep.cc",
            "memtable/skiplistrep.cc",
            "memtable/vectorrep.cc",
            "memtable/write_buffer_manager.cc",
            "monitoring/histogram.cc",
            "monitoring/histogram_windowing.cc",
            "monitoring/in_memory_stats_history.cc",
            "monitoring/instrumented_mutex.cc",
            "monitoring/iostats_context.cc",
            "monitoring/perf_context.cc",
            "monitoring/perf_level.cc",
            "monitoring/persistent_stats_history.cc",
            "monitoring/statistics.cc",
            "monitoring/thread_status_impl.cc",
            "monitoring/thread_status_updater.cc",
            "monitoring/thread_status_util.cc",
            "monitoring/thread_status_util_debug.cc",
            "options/cf_options.cc",
            "options/configurable.cc",
            "options/customizable.cc",
            "options/db_options.cc",
            "options/offpeak_time_info.cc",
            "options/options.cc",
            "options/options_helper.cc",
            "options/options_parser.cc",
            "port/mmap.cc",
            "port/stack_trace.cc",
            "table/adaptive/adaptive_table_factory.cc",
            "table/block_based/binary_search_index_reader.cc",
            "table/block_based/block.cc",
            "table/block_based/block_based_table_builder.cc",
            "table/block_based/block_based_table_factory.cc",
            "table/block_based/block_based_table_iterator.cc",
            "table/block_based/block_based_table_reader.cc",
            "table/block_based/block_builder.cc",
            "table/block_based/block_cache.cc",
            "table/block_based/block_prefetcher.cc",
            "table/block_based/block_prefix_index.cc",
            "table/block_based/data_block_hash_index.cc",
            "table/block_based/data_block_footer.cc",
            "table/block_based/filter_block_reader_common.cc",
            "table/block_based/filter_policy.cc",
            "table/block_based/flush_block_policy.cc",
            "table/block_based/full_filter_block.cc",
            "table/block_based/hash_index_reader.cc",
            "table/block_based/index_builder.cc",
            "table/block_based/index_reader_common.cc",
            "table/block_based/parsed_full_filter_block.cc",
            "table/block_based/partitioned_filter_block.cc",
            "table/block_based/partitioned_index_iterator.cc",
            "table/block_based/partitioned_index_reader.cc",
            "table/block_based/reader_common.cc",
            "table/block_based/uncompression_dict_reader.cc",
            "table/block_fetcher.cc",
            "table/cuckoo/cuckoo_table_builder.cc",
            "table/cuckoo/cuckoo_table_factory.cc",
            "table/cuckoo/cuckoo_table_reader.cc",
            "table/format.cc",
            "table/get_context.cc",
            "table/iterator.cc",
            "table/merging_iterator.cc",
            "table/compaction_merging_iterator.cc",
            "table/meta_blocks.cc",
            "table/persistent_cache_helper.cc",
            "table/plain/plain_table_bloom.cc",
            "table/plain/plain_table_builder.cc",
            "table/plain/plain_table_factory.cc",
            "table/plain/plain_table_index.cc",
            "table/plain/plain_table_key_coding.cc",
            "table/plain/plain_table_reader.cc",
            "table/sst_file_dumper.cc",
            "table/sst_file_reader.cc",
            "table/sst_file_writer.cc",
            "table/table_factory.cc",
            "table/table_properties.cc",
            "table/two_level_iterator.cc",
            "table/unique_id.cc",
            "test_util/sync_point.cc",
            "test_util/sync_point_impl.cc",
            "test_util/testutil.cc",
            "test_util/transaction_test_util.cc",
            "tools/block_cache_analyzer/block_cache_trace_analyzer.cc",
            "tools/dump/db_dump_tool.cc",
            "tools/io_tracer_parser_tool.cc",
            "tools/ldb_cmd.cc",
            "tools/ldb_tool.cc",
            "tools/sst_dump_tool.cc",
            "tools/trace_analyzer_tool.cc",
            "trace_replay/block_cache_tracer.cc",
            "trace_replay/io_tracer.cc",
            "trace_replay/trace_record_handler.cc",
            "trace_replay/trace_record_result.cc",
            "trace_replay/trace_record.cc",
            "trace_replay/trace_replay.cc",
            "util/async_file_reader.cc",
            "util/cleanable.cc",
            "util/coding.cc",
            "util/compaction_job_stats_impl.cc",
            "util/comparator.cc",
            "util/compression.cc",
            "util/compression_context_cache.cc",
            "util/concurrent_task_limiter_impl.cc",
            "util/crc32c.cc",
            "util/data_structure.cc",
            "util/dynamic_bloom.cc",
            "util/hash.cc",
            "util/murmurhash.cc",
            "util/random.cc",
            "util/rate_limiter.cc",
            "util/ribbon_config.cc",
            "util/slice.cc",
            "util/file_checksum_helper.cc",
            "util/status.cc",
            "util/stderr_logger.cc",
            "util/string_util.cc",
            "util/thread_local.cc",
            "util/threadpool_imp.cc",
            "util/udt_util.cc",
            "util/write_batch_util.cc",
            "util/xxhash.cc",
            "utilities/agg_merge/agg_merge.cc",
            "utilities/backup/backup_engine.cc",
            "utilities/blob_db/blob_compaction_filter.cc",
            "utilities/blob_db/blob_db.cc",
            "utilities/blob_db/blob_db_impl.cc",
            "utilities/blob_db/blob_db_impl_filesnapshot.cc",
            "utilities/blob_db/blob_dump_tool.cc",
            "utilities/blob_db/blob_file.cc",
            "utilities/cache_dump_load.cc",
            "utilities/cache_dump_load_impl.cc",
            "utilities/cassandra/cassandra_compaction_filter.cc",
            "utilities/cassandra/format.cc",
            "utilities/cassandra/merge_operator.cc",
            "utilities/checkpoint/checkpoint_impl.cc",
            "utilities/compaction_filters.cc",
            "utilities/compaction_filters/remove_emptyvalue_compactionfilter.cc",
            "utilities/counted_fs.cc",
            "utilities/debug.cc",
            "utilities/env_mirror.cc",
            "utilities/env_timed.cc",
            "utilities/fault_injection_env.cc",
            "utilities/fault_injection_fs.cc",
            "utilities/fault_injection_secondary_cache.cc",
            "utilities/leveldb_options/leveldb_options.cc",
            "utilities/memory/memory_util.cc",
            "utilities/merge_operators.cc",
            "utilities/merge_operators/bytesxor.cc",
            "utilities/merge_operators/max.cc",
            "utilities/merge_operators/put.cc",
            "utilities/merge_operators/sortlist.cc",
            "utilities/merge_operators/string_append/stringappend.cc",
            "utilities/merge_operators/string_append/stringappend2.cc",
            "utilities/merge_operators/uint64add.cc",
            "utilities/object_registry.cc",
            "utilities/option_change_migration/option_change_migration.cc",
            "utilities/options/options_util.cc",
            "utilities/persistent_cache/block_cache_tier.cc",
            "utilities/persistent_cache/block_cache_tier_file.cc",
            "utilities/persistent_cache/block_cache_tier_metadata.cc",
            "utilities/persistent_cache/persistent_cache_tier.cc",
            "utilities/persistent_cache/volatile_tier_impl.cc",
            "utilities/simulator_cache/cache_simulator.cc",
            "utilities/simulator_cache/sim_cache.cc",
            "utilities/table_properties_collectors/compact_for_tiering_collector.cc",
            "utilities/table_properties_collectors/compact_on_deletion_collector.cc",
            "utilities/trace/file_trace_reader_writer.cc",
            "utilities/trace/replayer_impl.cc",
            "utilities/transactions/lock/lock_manager.cc",
            "utilities/transactions/lock/point/point_lock_tracker.cc",
            "utilities/transactions/lock/point/point_lock_manager.cc",
            "utilities/transactions/lock/range/range_tree/range_tree_lock_manager.cc",
            "utilities/transactions/lock/range/range_tree/range_tree_lock_tracker.cc",
            "utilities/transactions/optimistic_transaction_db_impl.cc",
            "utilities/transactions/optimistic_transaction.cc",
            "utilities/transactions/pessimistic_transaction.cc",
            "utilities/transactions/pessimistic_transaction_db.cc",
            "utilities/transactions/snapshot_checker.cc",
            "utilities/transactions/transaction_base.cc",
            "utilities/transactions/transaction_db_mutex_impl.cc",
            "utilities/transactions/transaction_util.cc",
            "utilities/transactions/write_prepared_txn.cc",
            "utilities/transactions/write_prepared_txn_db.cc",
            "utilities/transactions/write_unprepared_txn.cc",
            "utilities/transactions/write_unprepared_txn_db.cc",
            "utilities/types_util.cc",
            "utilities/ttl/db_ttl_impl.cc",
            "utilities/wal_filter.cc",
            "utilities/write_batch_with_index/write_batch_with_index.cc",
            "utilities/write_batch_with_index/write_batch_with_index_internal.cc",
            "utilities/transactions/lock/range/range_tree/lib/locktree/concurrent_tree.cc",
            "utilities/transactions/lock/range/range_tree/lib/locktree/keyrange.cc",
            "utilities/transactions/lock/range/range_tree/lib/locktree/lock_request.cc",
            "utilities/transactions/lock/range/range_tree/lib/locktree/locktree.cc",
            "utilities/transactions/lock/range/range_tree/lib/locktree/manager.cc",
            "utilities/transactions/lock/range/range_tree/lib/locktree/range_buffer.cc",
            "utilities/transactions/lock/range/range_tree/lib/locktree/treenode.cc",
            "utilities/transactions/lock/range/range_tree/lib/locktree/txnid_set.cc",
            "utilities/transactions/lock/range/range_tree/lib/locktree/wfg.cc",
            "utilities/transactions/lock/range/range_tree/lib/standalone_port.cc",
            "utilities/transactions/lock/range/range_tree/lib/util/dbt.cc",
            "utilities/transactions/lock/range/range_tree/lib/util/memarena.cc",
        },
        .flags = &.{
            "-std=c++17",
            "-faligned-new",
            "-DHAVE_ALIGNED_NEW",
            "-DROCKSDB_UBSAN_RUN",
        },
    });

    // platform dependent stuff
    if (t.cpu.arch == .aarch64) {
        librocksdb.addCSourceFile(.{
            .file = rocks_dep.path("util/crc32c_arm64.cc"),
            .flags = &.{
                "-std=c++17",
                "-faligned-new",
                "-DHAVE_ALIGNED_NEW",
                "-DROCKSDB_UBSAN_RUN",
            },
        });
    }

    if (t.os.tag != .windows) {
        librocksdb.root_module.addCMacro("ROCKSDB_PLATFORM_POSIX", "");
        librocksdb.root_module.addCMacro("ROCKSDB_LIB_IO_POSIX", "");
        librocksdb.addCSourceFiles(.{
            .root = rocks_dep.path("."),
            .files = &.{
                "port/port_posix.cc",
                "env/env_posix.cc",
                "env/fs_posix.cc",
                "env/io_posix.cc",
            },
            .flags = &.{
                "-std=c++17",
                "-faligned-new",
                "-DHAVE_ALIGNED_NEW",
            },
        });
    } else {
        @panic("TODO: support windows!");
    }

    const os_name = switch (t.os.tag) {
        .macos => "OS_MACOSX",
        .linux => "OS_LINUX",
        else => std.debug.panic("TODO: support target OS '{s}'", .{@tagName(t.os.tag)}),
    };
    librocksdb.root_module.addCMacro(os_name, "");

    const build_version = b.addConfigHeader(.{
        .style = .{ .cmake = rocks_dep.path("util/build_version.cc.in") },
        .include_path = "util/build_version.cc",
    }, .{
        .GIT_MOD = 1,
    });
    librocksdb.addCSourceFile(.{ .file = build_version.getOutput() });

    b.installArtifact(librocksdb);
}
