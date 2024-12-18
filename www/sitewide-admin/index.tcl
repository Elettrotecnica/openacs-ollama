ad_page_contract {
    @author Gustaf Neumann

    @creation-date Aug 6, 2018
} {
}

set resource_info [::ollama_showdown::resource_info]
set version [dict get $resource_info configuredVersion]
set download_url [ad_conn url]/download?version=$version

set title "[dict get $resource_info resourceName] - Sitewide Admin"
set context [list $title]


# Local variables:
#    mode: tcl
#    tcl-indent-level: 4
#    indent-tabs-mode: nil
# End:
