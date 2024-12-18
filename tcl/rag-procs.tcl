ad_library {

    Retrieval Augmented Generation procs

}

namespace eval ollama {}
namespace eval ollama::rag {}

ad_proc -private ollama::rag::index_references {
    {-package_id ""}
    -query:required
    {-user_id ""}
} {
    Query the index and find references to be used for RAG.

    @param user enforce read permissions for this user. When not
           specified, we will treat the user as the public.
    @param package_id id of the ollama instance where RAG should be
           performed. This affects the references we are going to
           retrieve.

    @return list of references in dict format
} {
    set embedding [ollama::build_query -query $query]
    set embedding_size [llength $embedding]
    set embedding \[[join $embedding ,]\]

    set similarity_threshold [::parameter::get_global_value \
                                  -package_key ollama \
                                  -parameter similarity_threshold \
                                  -default 0.9]
    set top_k [::parameter::get_global_value \
                   -package_key ollama \
                   -parameter rag_top_k \
                   -default 5]

    if {$user_id eq ""} {
        set user_id [acs_magic_object the_public]
    }

    if {$package_id eq ""} {
        set package_clause ""
    } {
        set package_ids [::ollama::instance_relevant_packages -package_id $package_id]
        if {[llength $package_ids] == 0} {
            return
        }
        set package_clause "and o.package_id in ([join $package_ids ,])"
    }

    set references [list]
    db_foreach get_context [subst -nocommands {
        select i.index_id,
               i.object_id,
               i.content,
               i.embedding::vector($embedding_size) <=> :embedding as similarity
        from (select distinct orig_object_id
              from acs_permission.permission_p_recursive_array(array(
                select distinct i.object_id
                from ollama_ts_index i, acs_objects o
                where embedding::vector($embedding_size) <=> :embedding <= :similarity_threshold
                and o.object_id = i.object_id
                $package_clause
                ), :user_id, 'read')
              ) o,
              ollama_ts_index i
        where o.orig_object_id = i.object_id
        order by similarity asc
        fetch first :top_k rows only
    }] {
        set title [dict get [search::object_datasource -object_id $object_id] title]
        set url [search::object_url -object_id $object_id]
        lappend references [list \
                                index_id $index_id \
                                object_id $object_id \
                                content $content \
                                similarity $similarity \
                                url $url \
                                title $title]
    }

    return $references
}

ad_proc -private ::ollama::rag::fetch_pages {
    -urls:required
} {
    Fetches the content from a list of URLs via GET request. Does not
    follow links.

    @return a list of contents in respective order with the supplied
            URLs
} {
    return [lmap url $urls {
        set r [::util::http::get -url $url]
        ns_striphtml [expr {[dict get $r status] == 200 ? [dict get $r page] : ""}]
    }]
}

ad_proc -private ollama::rag::websearch_references {
    -query:required
} {
    Query the web and find references to be used for RAG.

    @return list of references in dict format
} {
    set top_k [::parameter::get_global_value \
                   -package_key ollama \
                   -parameter rag_top_k \
                   -default 5]

    #
    # We use the query as-is. It may be that we will need a
    # translation step, e.g. an LLM transforming the arbitrary text
    # into a search query.
    #
    ns_log notice \
        ollama::rag::websearch_references \
        "Searching the web"

    set urls [lrange [::ollama::search_engine::duckduckgo::search -query $query] 0 ${top_k}-1]

    ns_log notice \
        ollama::rag::websearch_references \
        "Fetching results"

    set pages [::ollama::rag::fetch_pages -urls $urls]

    set references [list]
    foreach page $pages url $urls {
        #
        # In the UI we expect index and object id to be there, so we
        # generate one.
        #
        set reference_id [ns_uuid]
        lappend references [list \
                                index_id $reference_id \
                                object_id $reference_id \
                                content $page \
                                similarity _ \
                                url $url \
                                title $url]
    }

    ns_log notice \
        ollama::rag::websearch_references \
        "We found [llength $references] references."

    return $references
}

ad_proc -private ollama::rag::context {
    {-package_id ""}
    -query:required
    {-user_id ""}
    -with_index:boolean
    -with_websearch:boolean
} {
    Builds the RAG context by fetching references relevant
    to the query and user supplied.

    @param package_id id of the ollama instance where RAG should be
           performed. This affects the references we are going to
           retrieve. By default, the whole index is searched.

    @return dict with generated context and references
} {
    if {![info exists package_id]} {
        set package_id [ad_conn package_id]
    }

    set references [list]
    if {$with_index_p} {
        lappend references {*}[::ollama::rag::index_references \
                                   -package_id $package_id \
                                   -query $query \
                                   -user_id $user_id]
    }
    if {$with_websearch_p} {
        lappend references {*}[::ollama::rag::websearch_references \
                                   -query $query]
    }

    if {[llength $references] == 0} {
        #
        # Nothing found, message stays the same.
        #
        set context $query
    } else {
        #
        # Found something, enhance the query with the extra knowledge.
        #
        set template [::parameter::get_global_value \
                          -package_key ollama \
                          -parameter rag_context_template]

        set context [join [lmap ref $references {
            dict get $ref content
        }] \n\n]
        set context [subst -nocommands $template]
    }

    #
    # It seems, we need this in order for ollama to accept our
    # message.
    #
    set context [encoding convertto $context]

    return [list \
                context $context \
                references $references]
}

namespace eval ::ollama::search_engine {}
namespace eval ::ollama::search_engine::duckduckgo {}

ad_proc -private ::ollama::search_engine::duckduckgo::search {
    -query:required
} {
    Performs a search on DuckDuckGo.

    @see https://duckduckgo.com/

    @return a list of URLs
} {
    set url [export_vars -base https://duckduckgo.com/ {{q $query}}]
    set r [::util::http::get -url $url]

    if {[dict get $r status] != 200} {
        set msg "Error when retrieving the homepage: [dict get $r status]"
        ns_log error $msg $r
        error $msg
    }

    if {![regexp \
              "href=\"(https://links.duckduckgo.com/d\.js\[^\"\]*)\"" \
              [dict get $r page] \
              _ \
              links_url]} {
        set msg "Cannot find URLs link..."
        ns_log error $msg [dict get $r page]
        error $msg
    }

    set r [::util::http::get -url $links_url]

    if {[dict get $r status] != 200} {
        set msg "Error when retrieving the links URL: [dict get $r status]"
        ns_log error $msg $r
        error $msg
    }

    set links [dict get $r page]
    set links [string range \
                   $links \
                   [string first "resultLanguages', " $links] \
                   end
                  ]
    set links [string range \
                   $links \
                   [string first "\[" $links]+1 \
                   [string first "\]" $links]-1 \
                  ]

    set links [lmap l [split $links ,] {
        string range $l 1 end-1
    }]

    return $links
}

#
# Local variables:
#    mode: tcl
#    tcl-indent-level: 4
#    indent-tabs-mode: nil
# End
