ad_library {

    ollama search engine driver installation procedures

}

namespace eval ollama {}
namespace eval ollama::install {}

ad_proc -private ollama::install::preinstall_checks {} {
    Ensure pgvector extension exists.
} {
    ns_log Notice " ********** STARTING BEFORE-INSTALL CALLBACK ****************"

    set extension_installed_p [db_0or1row check_extension {
        select 1 from pg_available_extensions where name = 'vector'
    }]

    if {!$extension_installed_p} {
        #
        # pgvector not installed
        #
        error {ollama::install::preinstall_checks -  pgvector extension not installed. Install pgvector manually. See https://github.com/pgvector/pgvector}
    }

    ns_log Notice " ********** ENDING BEFORE-INSTALL CALLBACK ****************"
}

ad_proc -private ollama::install::package_install {} {
    Installation callback for ollama search engine driver
} {
    ollama::install::register_fts_impl
    ollama::install::create_notification_types
}

ad_proc -private ollama::install::register_fts_impl {} {
    Register FtsEngineDriver service contract implementation
} {

    set spec {
        name "ollama-driver"
        aliases {
            search ollama::search
            index ollama::index
            unindex ollama::unindex
            update_index ollama::index
            summary ollama::summary
            info ollama::driver_info
        }
        contract_name "FtsEngineDriver"
        owner "ollama-driver"
    }

    acs_sc::impl::new_from_spec -spec $spec
}

ad_proc -private ollama::install::before_uninstall {} {
    Remove FtsEngineDriver service contract implementation
} {
    acs_sc::impl::delete \
        -contract_name "FtsEngineDriver" \
        -impl_name "ollama-driver"
    ollama::install::delete_notification_types
}

ad_proc -private ollama::install::create_notification_types {} {
    Create all ollama notification types.
} {
    #
    # This notification informs the user when all items in the
    # knowledge base have been indexed.
    #
    ollama::install::create_indexing_notification_type
}

ad_proc -private ollama::install::create_indexing_notification_type {} {
    Create the Notification types used to notify users whenever
    documents have been indexed.
} {
    set spec {
        contract_name "NotificationType"
        owner "ollama"
        name "ollama_index_notif_type"
        pretty_name "ollama_index_notif_type"
        aliases {
            GetURL       ollama::notification::get_url
            ProcessReply ollama::notification::process_reply
        }
    }
    set sc_impl_id [acs_sc::impl::new_from_spec -spec $spec]

    set type_id [notification::type::new \
                     -sc_impl_id $sc_impl_id \
                     -short_name "ollama_index_notif" \
                     -pretty_name "Indexing Notification" \
                     -description "Notifications informing the user when indexing documents in the knowledge base has finished."]

    # Enable the various intervals and delivery methods
    db_dml insert_intervals {
        insert into notification_types_intervals
        (type_id, interval_id)
        select :type_id, interval_id
        from notification_intervals where name in ('instant','hourly','daily')
    }
    db_dml insert_del_method {
        insert into notification_types_del_methods
        (type_id, delivery_method_id)
        select :type_id, delivery_method_id
        from notification_delivery_methods where short_name in ('email', 'sse')
    }
}


#
# Local variables:
#    mode: tcl
#    tcl-indent-level: 4
#    indent-tabs-mode: nil
# End:
