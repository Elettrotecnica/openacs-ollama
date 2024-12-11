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

    if {[::search::driver_name] eq ""} {
        parameter::set_value \
            -package_id [apm_package_id_from_key search] \
            -parameter FtsEngineDriver \
            -value ollama-driver
    }
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
}

#
# Local variables:
#    mode: tcl
#    tcl-indent-level: 4
#    indent-tabs-mode: nil
# End:
