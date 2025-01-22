#include <stdio.h>

#include "c.h"

char* path = "data";

int main() {
    const char* const cf_names = "default";
    const rocksdb_options_t* cf_options = rocksdb_options_create();
    rocksdb_column_family_handle_t* cf_handles;

    rocksdb_t* db;
    {
        rocksdb_options_t* db_options = rocksdb_options_create();
        rocksdb_options_set_create_if_missing(db_options, 1);
        char* errptr = NULL;
        db = rocksdb_open_column_families(
            db_options,
            path,
            1,
            &cf_names,
            &cf_options,
            &cf_handles,
            &errptr);
        if (errptr != NULL) {
            printf("error: %s", errptr);
            return 101;
        }
    }

    char delete_start = 182;
    char delete_end = 190;
    char get = 61;

    rocksdb_writebatch_t* batch = rocksdb_writebatch_create();
    rocksdb_writebatch_delete_range_cf(
        batch,
        cf_handles,
        &delete_start,
        1,
        &delete_end,
        1);

    {
        char* errptr = NULL;
        rocksdb_writeoptions_t* options = rocksdb_writeoptions_create();
        rocksdb_write(db, options, batch, &errptr);
        if (errptr != NULL) {
            printf("error: %s", errptr);
            return 101;
        }
    }

    {
        char* errptr = NULL;
        rocksdb_readoptions_t* read_options = rocksdb_readoptions_create();
        size_t vallen = 0;
        rocksdb_get_cf(
            db,
            read_options,
            cf_handles,
            &get,
            1,
            &vallen,
            &errptr);
        if (errptr != NULL) {
            printf("error: %s", errptr);
            return 101;
        }
    }

    printf("it works");
}
