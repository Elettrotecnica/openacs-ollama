ad_page_contract {

    Delete a conversation.

} {
    conversation_id:object_type(ollama_conversation),notnull
}

set user_id [ad_conn user_id]

::permission::require_permission \
    -party_id $user_id \
    -object_id $conversation_id \
    -privilege delete

db_1row delete_conversation {
    select acs_object__delete(:conversation_id)
    from dual
}

ad_returnredirect -message "Conversation was deleted." .
ad_script_abort
