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

    db_dml save_token {
        update ollama_conversation_messages set
        content = coalesce(content, '') || :content
        where message_id = :message_id
    }
}



ad_proc -private ollama::conversation::generate_title {
    -conversation_id:required
} {
    Produce a title from the contents of this conversation and save
    it.
} {
    if {[db_0or1row get_first_message {
        select content, model
        from ollama_conversation_messages
        where conversation_id = :conversation_id
        order by timestamp asc
        fetch first 1 rows only
    }]} {
        ns_log notice \
            ollama::conversation::generate_title \
            $conversation_id \
            "Generating..."

        ::ollama::API create titler -model $model

        set message [string trim [subst -nocommands {
            Generate a suitable title for the message enclosed within
            <message></message> XML tags. Generate the title and
            nothing else. Ensure the title is in the same language as
            the message. Keep the title short! Should not be longer
            than a single sentence.

            <message>$content</message>
        }]]

        set response [titler chat \
                          -messages [list \
                                         [list role user content $message]]]

        ns_log notice \
            ollama::conversation::generate_title \
            $conversation_id \
            "Response received" \
            $response

        package require json
        set title [dict get [dict get \
                                 [::json::json2dict \
                                      [dict get $response body] \
                                     ] message] content]
        #
        # Hack: DeepSeek will always output its Chain of Thought
        # before a reply. We do not want that.
        #
        regsub {^\s*<think>.*</think>\s*} $title {} title

        #
        # Don't hit the 1000 acs_objects.title character limit.
        #
        set title [string range $title 0 999]

        ns_log notice \
            ollama::conversation::generate_title \
            $conversation_id \
            "Title extracted" \
            $title

        db_dml save_title {
            update acs_objects set
            title = :title
            where object_id = :conversation_id
        }

        ns_log notice \
            ollama::conversation::generate_title \
            $conversation_id \
            "Title saved"
    }
}
