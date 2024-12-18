ad_page_contract {

    A simple RAG implementation

} {
    {message ""}
    {conversation_id:naturalnum ""}
    model:optional
}

set user_id [ad_conn user_id]
set package_id [ad_conn package_id]
set peeraddr [ad_conn peeraddr]

::permission::require_permission \
    -party_id $user_id \
    -object_id $package_id \
    -privilege read

set knowledge_packages [list]
foreach knowledge_package_id [::ollama::instance_relevant_packages -package_id $package_id] {
    lappend knowledge_packages [::site_node::get_from_object_id -object_id $knowledge_package_id]
}
::template::util::list_to_multirow knowledge $knowledge_packages
::template::multirow sort knowledge url
::template::multirow sort knowledge instance_name

set actions [list \
                 "New conversation" converse "Start a new conversation" \
                ]


::template::list::create \
    -name conversations \
    -multirow conversations \
    -key conversation_id \
    -actions $actions \
    -page_size 30 \
    -page_groupsize 10 \
    -page_query {
        select object_id as conversation_id
        from acs_objects o
        where object_type = 'ollama_conversation'
        and package_id = :package_id
        order by (select min(timestamp)
                  from ollama_conversation_messages
                  where conversation_id = o.object_id),
                 title
    } \
    -elements {
        title {
            label {Title}
            link_url_col conversation_url
        }
        first_message {
            label {First Message}
        }
        last_message {
            label {Last Message}
        }
        n_messages {
            label {N. Messages}
        }
        delete_link {
            label ""
            link_html {class delete}
            display_template {Delete}
            link_url_col delete_url
        }
    }

::template::add_confirm_handler -event click -selector .delete

db_multirow -extend {
    conversation_url
    delete_url
} conversations get_conversations [subst {
    select c.conversation_id,
           o.title,
           count(*) as n_messages,
           max(m.timestamp) as last_message,
           min(m.timestamp) as first_message
      from ollama_conversations c,
           acs_objects o,
           ollama_conversation_messages m
    where o.object_id = c.conversation_id
      and m.conversation_id = c.conversation_id
      and [::template::list::page_where_clause -name conversations -key c.conversation_id]
     group by c.conversation_id, o.object_id
    order by first_message asc, title asc
}] {
    set first_message [lc_time_fmt $first_message "%x %X"]
    set last_message [lc_time_fmt $last_message "%x %X"]

    set conversation_url converse?conversation_id=$conversation_id
    set delete_url delete?conversation_id=$conversation_id
}
