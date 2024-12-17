ad_library {

    Retrieval Augmented Generation procs

}

namespace eval ollama {}
namespace eval ollama::rag {}

ad_proc -private ollama::rag::references {
    {-package_id ""}
    -query:required
    {-user_id ""}
    {-top_k ""}
    {-similarity_threshold ""}
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

    if {$similarity_threshold eq ""} {
        set similarity_threshold [::parameter::get_global_value \
                                      -package_key ollama \
                                      -parameter similarity_threshold \
                                      -default 0.9]
    }
    if {$top_k eq ""} {
        set top_k [::parameter::get_global_value \
                       -package_key ollama \
                       -parameter rag_top_k \
                       -default 5]
    }

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

ad_proc -private ollama::rag::context {
    {-package_id ""}
    -query:required
    {-user_id ""}
    {-top_k ""}
    {-similarity_threshold ""}
    {-template ""}
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

    if {$template eq ""} {
        set template [::parameter::get_global_value \
                          -package_key ollama \
                          -parameter rag_context_template]
    }

    set references [ollama::rag::references \
                        -package_id $package_id \
                        -query $query \
                        -user_id $user_id \
                        -top_k $top_k \
                        -similarity_threshold $similarity_threshold]

    set context [join [lmap ref $references {
        dict get $ref content
    }] \n\n]
    set context [subst -nocommands $template]

    #
    # It seems, we need this in order for ollama to accept our
    # message.
    #
    set context [encoding convertto $context]

    return [list \
                context $context \
                references $references]
}

#
# Local variables:
#    mode: tcl
#    tcl-indent-level: 4
#    indent-tabs-mode: nil
# End
