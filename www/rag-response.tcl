ad_page_contract {

    Streaming backend to the LLM

} {
    message:allhtml,notnull
}

#
# The reply may take seconds or longer to complete. We move everything
# to the background.
#

set handler [::ollama::background_reply_handler]

ad_schedule_proc -thread t -once t 0 ::apply {{message handler} {
    ::ollama::API create chatter -model llama3.2

    chatter chat \
        -handler $handler \
        -messages [list \
                       [list \
                            role "user" \
                            content $message \
                           ]]
}} $message $handler
