ad_page_contract {

    Streaming backend to the LLM

} {
    message:allhtml,notnull
}

#
# The reply may take seconds or longer to complete. We move everything
# to the background.
#

ns_write "HTTP/1.0 200 OK\r\nContent-type: text/plain\r\n\r\n"

set channel [ns_connchan detach]

ad_schedule_proc -thread t -once t 0 ::apply {
    {
        message
        channel
    } {
        ::ollama::API create chatter -model llama3.2

        set handler [list ::apply {{channel socket token} {
            ns_connchan write -buffered $channel [read $socket]
        }} $channel]

        chatter chat \
            -handler $handler \
            -messages [list \
                           [list \
                                role "user" \
                                content $message \
                               ]]
    }
} $message $channel
