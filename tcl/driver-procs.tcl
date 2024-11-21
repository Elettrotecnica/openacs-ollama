ad_library {

    FtsEngineDriver Service Contract implementations.

}

namespace eval ollama {}

ad_proc -public ollama::index {
    object_id
    txt
    title
    keywords
} {
    Add or update an object in the index.
} {
    #
    # We do not actually index here, because we want to batch the
    # embeddings.
    #
    set package_id [apm_package_id_from_key ollama]

    set chunk_size [parameter::get \
                        -package_id $package_id \
                        -parameter indexing_chunk_size \
                        -default 1000]

    set chunk_overlap [parameter::get \
                           -package_id $package_id \
                           -parameter indexing_chunk_overlap \
                           -default 100]

    db_transaction {
        db_dml clear_entries {
            delete from ollama_ts_index
            where object_id = :object_id
        }
        set content [join [list $title $keywords $txt]]
        set content [regexp -all -inline {\S+} $content]
        while {[llength $content] > 0} {
            set chunk [lrange $content 0 $chunk_size]
            set start [expr {max($chunk_size - $chunk_overlap, 1)}]
            set content [lrange $content $start end]
            db_dml index {
                insert into ollama_ts_index
                (object_id, content)
                values
                (:object_id, :chunk)
            }
        }
    }
}

ad_proc -private ollama::batch_index {} {
    Batch index entries without embeddings.
} {
    if {[nsv_incr ollama batch_embeddings_p] == 1} {
        set package_id [apm_package_id_from_key ollama]

        set model [parameter::get \
                       -package_id $package_id \
                       -parameter embedding_model]

        set host [parameter::get \
                      -package_id $package_id \
                      -parameter ollama_host]

        set batch_size [parameter::get \
                            -package_id $package_id \
                            -parameter embedding_batch_size \
                            -default 50]

        try {
            set indexes [list]
            set input [list]
            db_foreach get_unindexed_entries {
                select index_id, content
                from ollama_ts_index
                where embedding is null
                fetch first :batch_size rows only
            } {
                lappend indexes $index_id
                #
                # Ollama will reject requests containing what it deems
                # invalid UTF-8...
                #
                lappend input [encoding convertto $content]
            }

            if {[llength $indexes] > 0} {
                ::ollama::API create indexer \
                    -model $model \
                    -host $host

                set response [indexer embed -input $input]
                # ns_log warning $response

                package require json
                set embeddings [dict get \
                                    [::json::json2dict \
                                         [dict get $response page]\
                                        ] embeddings]

                foreach index_id $indexes embedding $embeddings {
                    set embedding \[[join $embedding ,]\]

                    db_dml store_embedding {
                        update ollama_ts_index set
                        embedding = :embedding
                        where index_id = :index_id
                    }
                }
            } else {
                ns_log notice "ollama::batch_index: nothing to index"
            }

        } finally {
            nsv_unset ollama batch_embeddings_p
        }
    } else {
        ns_log notice "ollama::batch_index: indexing still in progress"
    }
}

ad_proc -public ollama::unindex {
    object_id
} {
    Remove item from the index
} {
    db_dml unindex {
        delete from ollama_ts_index
        where object_id = :object_id
    }
}

ad_proc -callback search::search -impl ollama-driver {
    -query
    {-user_id 0}
    {-offset 0}
    {-limit 10}
    {-df ""}
    {-dt ""}
    {-package_ids ""}
    {-object_type ""}
    {-extra_args {}}
} {
    FtsEngineDriver search operation implementation for ollama.
} {
    set package_id [apm_package_id_from_key ollama]
    set similarity_threshold [parameter::get \
                                  -package_id $package_id \
                                  -parameter similarity_threshold \
                                  -default 0.9]

    set embedding [ollama::build_query -query $query]
    set embedding_size [llength $embedding]
    set embedding \[[join $embedding ,]\]

    ns_log warning $embedding

    set where_clauses ""
    set from_clauses ""

    set need_acs_objects 0
    if {$df ne ""} {
        set need_acs_objects 1
        lappend where_clauses "o.creation_date > :df"
    }
    if {$dt ne ""} {
        set need_acs_objects 1
        lappend where_clauses "o.creation_date < :dt"
    }

    foreach {arg value} $extra_args {
        set arg_clauses [lindex [callback \
                                     -impl $arg \
                                     search::extra_arg \
                                     -value $value \
                                     -object_table_alias "o"] 0]
        if {
            [dict exists $arg_clauses from_clause] &&
            [dict get $arg_clauses from_clause] ne ""
        } {
            lappend from_clauses [dict get $arg_clauses from_clause]
        }
        if {
            [dict exists $arg_clauses where_clause] &&
            [dict get $arg_clauses where_clause] ne ""
        } {
            lappend where_clauses [dict get $arg_clauses where_clause]
        }
    }
    if {[llength $extra_args]} {
        # extra_args can assume a join on acs_objects
        set need_acs_objects 1
    }
    if {[llength $package_ids] > 0} {
        set need_acs_objects 1
        lappend where_clauses "o.package_id in ([ns_dbquotelist $package_ids])"
    }
    if {$need_acs_objects} {
        lappend from_clauses "ollama_ts_index index" "acs_objects o"
        lappend where_clauses "o.object_id = index.object_id"
    } else {
        lappend from_clauses "ollama_ts_index index"
    }

    set from_clauses [join $from_clauses ,]

    if {[llength $where_clauses]} {
        set where_clauses " and [join $where_clauses { and }]"
    }

    #
    # Casting to a vector with the exact embedding size is needed to
    # use indexes, because we do not hardcode the embedding size in
    # the index table. See
    # https://github.com/pgvector/pgvector?tab=readme-ov-file#can-i-store-vectors-with-different-dimensions-in-the-same-column
    #
    set results_ids [db_list search [subst -nocommands {
        select orig_object_id, max(i.embedding::vector($embedding_size) <=> :embedding)
          from acs_permission.permission_p_recursive_array(array(
                 select index.object_id
                 from $from_clauses
                 where o.object_id = index.object_id
                   and index.embedding::vector($embedding_size) <=> :embedding <= :similarity_threshold
                   $where_clauses
                 ), :user_id, 'read') o,
              ollama_ts_index i
        where o.orig_object_id = i.object_id
        group by orig_object_id
        order by 2
        fetch first :limit rows only
        offset :offset
    }]]

    set count [db_string count [subst -nocommands {
        select count(*) from (
        select distinct(orig_object_id) from acs_permission.permission_p_recursive_array(array(
           select index.object_id
           from $from_clauses
           where o.object_id = index.object_id
             and index.embedding::vector($embedding_size) <=> :embedding <= :similarity_threshold
             $where_clauses
        ), :user_id, 'read')) t
    }] -default 0]

    set stop_words {}

    #
    # Lovely the search package requires count to be returned but the
    # service contract definition doesn't specify it!
    #
    return [list ids $results_ids stopwords $stop_words count $count]
}

ad_proc -public ollama::summary {
    query
    txt
} {
    Highlights matching terms.

    Behaves similar to Postgres ts_headline

    @see https://www.postgresql.org/docs/current/textsearch-controls.html#TEXTSEARCH-HEADLINE

    @return summary containing search query terms
} {
    set query_words [lsort -unique \
                         [regexp -all -inline {\S+} \
                              [string tolower $query]]]

    set n_query_words [llength $query_words]

    set max_words 35
    set max_occurrences 0
    set best_chunk ""

    set txt [regexp -all -inline {\S+} $txt]
    while {[llength $txt] > 0} {
        set chunk [lrange $txt 0 $max_words]
        set txt [lrange $txt $max_words end]

        set occurrences 0
        set match_chunk [lsort -unique [lmap word $chunk {
            string tolower $word
        }]]
        foreach word $query_words {
            incr occurrences [expr {$word in $match_chunk}]
        }
        if {$occurrences > $max_occurrences} {
            set max_occurrences $occurrences
            set best_chunk $chunk
        }
        if {$occurrences == $n_query_words} {
            break
        }
    }

    regsub -nocase -all -- \
        "((^|\[^a-zA-Z0-9\])(([join $query_words |])( ([join $query_words |]))*)($|\[^a-zA-Z0-9\]))" \
        [join $best_chunk] {\2<b>\3</b>\7} best_chunk

    return $best_chunk
}

ad_proc -callback search::driver_info -impl ollama-driver {
} {
    Search driver info callback
} {
    return [ollama::driver_info]
}

ad_proc -private ollama::driver_info {} {
    Driver information.
} {
    return [list \
                package_key ollama-driver \
                version 1 \
                automatic_and_queries_p 0 \
                stopwords_p 1]
}

ad_proc -private ollama::build_query {
    -query
} {
    Build query string for ollama

    @param query string to convert
    @return returns formatted query string for ollama tsquery
} {
    set package_id [apm_package_id_from_key ollama]
    set model [parameter::get \
                   -package_id $package_id \
                   -parameter embedding_model]

    set host [parameter::get \
                  -package_id $package_id \
                  -parameter ollama_host]

    ::ollama::API create indexer \
        -model $model \
        -host $host

    set response [indexer embed -input [list $query]]

    package require json

    try {
        set embeddings [dict get \
                            [::json::json2dict \
                                 [dict get $response page]\
                                ] embeddings]
    } on error {errmsg} {
        ns_log error \
            "Invalid response from embedding endpoint:" $errmsg \
            indexer: [indexer serialize] \
            response: $response
        error "Invalid response from embedding endpoint: $errmsg"
    }

    return [lindex $embeddings 0]
}

#
# Local variables:
#    mode: tcl
#    tcl-indent-level: 4
#    indent-tabs-mode: nil
# End:
