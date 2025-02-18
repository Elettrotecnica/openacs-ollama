ad_library {

    Procs concerning Notifications

}

namespace eval ollama {}
namespace eval ollama::notification {}

ad_proc -private ollama::notification::index_notification {
    {-package_id:required}
} {
    Perform the notifications.
} {
    set node [::site_node::get_from_object_id -object_id $package_id]

    set instance_name [dict get $node instance_name]
    set package_url [dict get $node url]

    set subject "\[${instance_name}\] #ollama.indexing_complete#"
    set text_version "\[${instance_name}\](${package_url}) #ollama.has_finsihed_indexing#"
    set html_version "<a href='${package_url}'>${instance_name}</a> #ollama.has_finsihed_indexing#"

    # Do the notification for the forum
    ::notification::new \
        -type_id [notification::type::get_type_id \
                      -short_name ollama_index_notif] \
        -object_id $package_id \
        -response_id $package_id \
        -object_id $package_id \
        -notif_subject $subject \
        -notif_text $text_version \
        -notif_html $html_version
}

ad_proc -private ollama::notification::sweep_indexed_packages {} {
    As soon as a package that was being indexed has completed, notify
    the users about it.
} {
}

ad_proc -private ollama::notification::get_url {
    object_id
} {
    Assumes a package as input. Returns the package URL.
} {
    return [apm_package_url_from_id $object_id]
}

ad_proc -private ollama::notification::process_reply {
    reply_id
} {
    A noop to implement the Service Contract.
} {
}

