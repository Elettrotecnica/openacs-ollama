ad_page_contract {

    Streaming backend to the LLM

} {
    conversation_id:object_id,notnull
    model:notnull
}

set user_id [ad_conn user_id]

::permission::require_permission \
    -party_id $user_id \
    -object_id $conversation_id \
    -privilege write

#
# The reply may take seconds or longer to complete. We move everything
# to the background.
#

db_1row start_reply_message {
    with start as (
                   insert into ollama_conversation_messages
                   (conversation_id, role, model)
                   values
                   (:conversation_id, 'assistant', :model)
                   returning *
                   )
    select message_id from start
}

set channel [ns_connchan detach]

ad_schedule_proc -thread t -once t 0 ::apply {
    {
        model
        channel
        message_id
    } {
        ::ollama::API create chatter -model $model

        set messages [list]
        foreach m [db_list_of_ns_sets get_messages {
            select rag, content, role
            from ollama_conversation_messages
            where conversation_id = (select conversation_id
                                     from ollama_conversation_messages
                                     where message_id = :message_id)
              and message_id <> :message_id
            order by timestamp asc
        }] {
            set message [ns_set array $m]

            #
            # The message we send as context to the LLM is the
            # rag-augmented one, when relevant references have been
            # found.
            #
            set rag [dict get $message rag]
            if {[dict exists $rag references] &&
                [llength [dict get $rag references]] > 0} {
                dict set message content [dict get $rag context]
            }
            dict unset message rag

            lappend messages $message
        }

        set handler [list ::apply {{channel message_id d} {
            dict with d {
                if {[info exists status]} {
                    ns_log warning "Start reply"
                    #
                    # Headers have been received.
                    #
                    set response "HTTP/1.1 $status $phrase\r\n"
                    foreach {key value} [ns_set array $headers] {
                        append response "$key: $value\r\n"
                    }
                    append response \r\n
                    ns_log warning headers $response
                    ns_connchan write $channel $response
                } else {
                    #
                    # Response is coming through. Save it and relay to
                    # the client.
                    #
                    ns_log warning {Received data} $data
                    ollama::conversation::save_reply \
                        -message_id $message_id \
                        -token $data
                    ns_connchan write $channel [encoding convertto $data]
                }
            }
        }} $channel $message_id]


        chatter chat \
            -handler $handler \
            -messages $messages
    }

} $model $channel $message_id
