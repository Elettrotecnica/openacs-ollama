ad_page_contract {

    A simple RAG implementation

} {
    {message ""}
}

::template::head::add_css \
    -href /resources/acs-templating/modal.css
::template::head::add_javascript \
    -src /resources/acs-templating/modal.js

if {$message ne ""} {
    #
    # Enhance the query with the context coming from our documents.
    #
    set rag [ollama::rag::context -query $message]

    #
    # Display the document context to the users.
    #
    ::template::util::list_to_multirow references \
        [dict get $rag references]

    set rag_message [dict get $rag context]

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

                const url = 'rag-response';
                const response = await fetch(url, {
                    method: 'POST',
                    body: formData,
                });

                const reader = response.body.pipeThrough(new TextDecoderStream()).getReader();

                while (true) {
                    const {value, done} = await reader.read();
                    if (done) break;
                    const r = JSON.parse(value);
                    reply.textContent+= r.message.content;
                }
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

ad_form -name chat -form {
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


