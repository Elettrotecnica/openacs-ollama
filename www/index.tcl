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
            const formData = new FormData();
            const message = document.querySelector('#rag-message').textContent;
            formData.append('message', message);
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
        }

        readData();
    }
}

ad_form -name chat -form {
    {message:text(textarea)
        {label {Message}}
    }
} -on_request {

} -on_submit {
}


