ad_library {
    Conversation procs.
}

namespace eval ollama {}
namespace eval ollama::conversation {}

ad_proc -private ollama::conversation::save_reply {
    -message_id:required
    -token:required
} {
    Trick to get the query dispatcher to tell what query we want to
    run even in the http callback.
} {
    if {$token eq ""} {
        return
    }

    package require json
    set token [::json::json2dict $token]
    set content [dict get [dict get $token message] content]

    if {$content eq ""} {
        #
        # The last message is normally empty and will be treated as
        # null, ereasing the message on concatenation. We just skip
        # it.
        #
        return
    }

    set content [encoding convertfrom $content]

    db_dml save_token {
        update ollama_conversation_messages set
        content = coalesce(content, '') || :content
        where message_id = :message_id
    }
}
