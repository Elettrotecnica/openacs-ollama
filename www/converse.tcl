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

if {$conversation_id eq ""} {
    ::permission::require_permission \
        -party_id $user_id \
        -object_id $package_id \
        -privilege write

    #
    # Start of a new conversation. Title is empty at first.
    #
    db_1row start_conversation {
        with start as (
                       insert into ollama_conversations
                       (
                        conversation_id
                        ) values (
                                  (select acs_object__new(
                                                         null,
                                                         'ollama_conversation',
                                                         current_timestamp,
                                                         :user_id,
                                                         :peeraddr,
                                                         :package_id,
                                                         't',
                                                         null,
                                                         :package_id
                                                         ))
                                  )
                       returning *
                       )
        select conversation_id from start;
    }
} else {
    ::permission::require_permission \
        -party_id $user_id \
        -object_id $conversation_id \
        -privilege write
}

::template::head::add_css \
    -href /resources/acs-templating/modal.css
::template::head::add_javascript \
    -src /resources/acs-templating/modal.js

::template::head::add_javascript \
    -src https://cdn.jsdelivr.net/npm/showdown@2.1.0/dist/showdown.min.js

::template::add_body_handler -event load -script {
    const converter = new showdown.Converter();
    for (const message of document.querySelectorAll('.markdown')) {
       message.innerHTML = converter.makeHtml(message.textContent);
    }
}

if {$message ne ""} {
    #
    # Enhance the query with the context coming from our documents.
    #
    set rag [::ollama::rag::context \
                 -user_id $user_id \
                 -package_id $package_id \
                 -query $message]

    set n_messages [db_string save_message {
        with insert as (
                        insert into ollama_conversation_messages
                        (conversation_id, content, rag, role, model)
                        values
                        (:conversation_id, :message, :rag, 'user', :model)
                        )
        select count(*) from ollama_conversation_messages
        where conversation_id = :conversation_id
    }]

    if {$n_messages == 0} {
        ollama::conversation::generate_title \
            -conversation_id $conversation_id
    }

    if {[llength [dict get $rag references]] > 0} {
        set rag_message [dict get $rag context]
    } else {
        set rag_message $message
    }

    #
    # Connect to the streaming backend to receive the reply from the
    # model.
    #
    ::template::add_body_handler -event load -script {
        async function readData() {
            const form = document.querySelector('#chat');
            const fields = form.querySelectorAll('input,textarea,button,select');
            for (const field of fields) {
                field.disabled = true;
            }
            try {
                const formData = new FormData();

                const message = document.querySelector('#rag-message').textContent;
                formData.append('message', message);

                const model = document.querySelector('#chat [name=model]').value;
                formData.append('model', model);

                const conversationId = document.querySelector('#chat [name=conversation_id]').value;
                formData.append('conversation_id', conversationId);

                const url = 'rag-response';
                const response = await fetch(url, {
                    method: 'POST',
                    body: formData,
                });

                const reply = document.querySelector('#reply');
                reply.dataset.text = '';

                const reader = response.body.pipeThrough(new TextDecoderStream()).getReader();

                const converter = new showdown.Converter();

                let text = '';
                while (true) {
                    const {value, done} = await reader.read();
                    if (done) {
                        break;
                    }
                    text += value.substring(0, value.indexOf('\n'));
                    try {
                        const r = JSON.parse(text);
                        text = '';
                        reply.textContent+= r.message.content;
                        if (r.done) {
                            break;
                        }
                    } catch (e) {
                        text += value.substring(value.indexOf('\n'));
                        console.log('PARTIAL READ');
                    }
                }

                reader.cancel();

            } catch (e) {
                console.error(e);
                alert(e.message);
            } finally {
                for (const field of fields) {
                    field.disabled = false;
                }
            }
        }

        readData();
    }
}

set conversation_title [db_string get_title {
    select title from acs_objects
    where object_id = :conversation_id
}]

set context [list $conversation_title]

db_multirow messages get_messages {
    select message_id, timestamp, role, content, rag
    from ollama_conversation_messages
    where conversation_id = :conversation_id
    order by timestamp asc
} {
    if {[dict exists $rag references] && [llength [dict get $rag references]] > 0} {
        unset -nocomplain refs
        set rag <h2>References:</h2><ul>[join [lmap ref [dict get $rag references] {
            set count [incr refs([dict get $ref object_id])]
            set count [expr {$count == 1 ? "" : " - $count"}]
            subst {
             <li>
              <div id="modal-[dict get $ref index_id]" class="acs-modal">
               <div class="acs-modal-content">
                <h3>[ns_quotehtml [dict get $ref title]]$count</h3>
                <p>[ns_quotehtml [dict get $ref content]]</p>
                <p><a
                      href="[ns_quotehtml [dict get $ref url]]"
                      target="_blank">#acs-subsite.See_full_size#</a></p>
                <p>Similarity: [dict get $ref similarity]</p>
                <button class="acs-modal-close">Close</button>
               </div>
              </div>
              <a
                 class="acs-modal-open"
                 data-target="#modal-[dict get $ref index_id]"
                 href="#">[ns_quotehtml [dict get $ref title]]$count
              </a>
             </li>
            }
        }]]</ul>
    } else {
        set rag ""
    }
}


set models [list]
::ollama::API create ollama

set selected_model [ollama model]

foreach option [ollama models] {
    set option [dict get $option name]
    if {[lindex [split $option :] 0] eq $selected_model} {
        set selected_model $option
    }
    lappend models \
        [list $option $option]
}

ad_form \
    -name chat \
    -export {conversation_id} \
    -form {
        {message:text(textarea)
            {label {Message}}
        }
        {model:text(select)
            {label {Model}}
            {options $models}
            {value $selected_model}
        }
    } -on_request {

    } -on_submit {
    }


