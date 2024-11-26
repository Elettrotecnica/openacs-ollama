ad_library {

    Retrieval Augmented Generation procs

}

namespace eval ollama {}
namespace eval ollama::rag {}

ad_proc -public ollama::rag::references {
    -query:required
    {-user_id ""}
    {-top_k ""}
    {-similarity_threshold ""}
} {
    Query the index and find references to be used for RAG.

    @param user enforce read permissions for this user. When not
           specified, we will treat the user as the public.

    @return list of references in dict format
} {
    set embedding [ollama::build_query -query $query]
    set embedding_size [llength $embedding]
    set embedding \[[join $embedding ,]\]

    set package_id [apm_package_id_from_key ollama]

    if {$similarity_threshold eq ""} {
        set similarity_threshold [parameter::get \
                                      -package_id $package_id \
                                      -parameter similarity_threshold \
                                      -default 0.9]
    }
    if {$top_k eq ""} {
        set top_k [parameter::get \
                       -package_id $package_id \
                       -parameter rag_top_k \
                       -default 5]
    }

    if {$user_id eq ""} {
        set user_id [acs_magic_object the_public]
    }

    set references [list]
    db_foreach get_context [subst -nocommands {
        select i.object_id,
               i.content,
               i.embedding::vector($embedding_size) <=> :embedding as similarity
        from (select distinct orig_object_id
              from acs_permission.permission_p_recursive_array(array(
                select distinct object_id
                from ollama_ts_index
                where embedding::vector($embedding_size) <=> :embedding <= :similarity_threshold
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
                                object_id $object_id \
                                content $content \
                                similarity $similarity \
                                url $url \
                                title $title]
    }

    return $references
}

ad_proc -public ollama::rag::context {
    -query:required
    {-user_id ""}
    {-top_k ""}
    {-similarity_threshold ""}
    {-template ""}
} {
    Builds the RAG context by fetching references relevant
    to the query and user supplied.

    @return dict with generated context and references
} {
    if {$template eq ""} {
        set package_id [apm_package_id_from_key ollama]
        set template [parameter::get \
                          -package_id $package_id \
                          -parameter rag_context_template]
    }

    set references [ollama::rag::references \
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
