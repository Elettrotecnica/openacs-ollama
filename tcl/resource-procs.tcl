ad_library {

    Showdown Markdown-to-HTML library management.

    @author Antonio Pisano

}

namespace eval ::ollama_showdown {
    variable parameter_info

    #
    # The Showdown version configuration can be tailored via the OpenACS
    # configuration file:
    #
    # ns_section ns/server/${server}/acs/ollama
    #        ns_param ShowdownVersion 2.1.0
    #
    set parameter_info {
        package_key ollama
        parameter_name ShowdownVersion
        default_value 2.1.0
    }

    ad_proc resource_info {
        {-version ""}
    } {
        @return a dict in "resource_info" format, compatible with
                other API and templates on the system.

        @see util::resources::can_install_locally
        @see util::resources::is_installed_locally
        @see util::resources::download
        @see util::resources::version_segment
    } {
        variable parameter_info

        #
        # If no version is specified, use configured one
        #
        if {$version eq ""} {
            dict with parameter_info {
                set version [::parameter::get_global_value \
                                 -package_key $package_key \
                                 -parameter $parameter_name \
                                 -default $default_value]
            }
        }

        #
        # Setup variables for access via CDN vs. local resources.
        #
        #   "resourceDir"    is the absolute path in the filesystem
        #   "versionSegment" is the version-specific element both in the
        #                    URL and in the filesystem.
        #

        set resourceDir    [acs_package_root_dir ollama/www/resources/showdown]
        set versionSegment $version
        set cdnHost        cdnjs.cloudflare.com
        set cdn            //$cdnHost/

        set cspMap ""

        if {[file exists $resourceDir/$versionSegment]} {
            #
            # Local version is installed
            #
            set prefix /resources/ollama/showdown/$versionSegment
            set cdnHost ""
        } else {
            #
            # Use CDN
            #
            set prefix ${cdn}ajax/libs/showdown/$versionSegment
        }

        dict set URNs urn:ad:js:ollama-showdown showdown.min.js

        set major [lindex [split $version .] 0]

        #
        # Return the dict with at least the required fields
        #
        lappend result \
            resourceName "Showdown" \
            resourceDir $resourceDir \
            cdn $cdn \
            cdnHost $cdnHost \
            prefix $prefix \
            cssFiles {} \
            jsFiles  {} \
            extraFiles {} \
            downloadURLs [subst {
                https://api.github.com/repos/showdownjs/showdown/zipball/$version
            }] \
            urnMap $URNs \
            cspMap $cspMap \
            versionCheckAPI {cdn cdnjs library showdown count 5} \
            vulnerabilityCheck {service snyk library showdown} \
            parameterInfo $parameter_info \
            configuredVersion $version

        return $result
    }

    ad_proc -private download {
        {-version ""}
    } {

        Download the package for the configured version and put it
        into a directory structure similar to the CDN structure to
        allow installation of multiple versions.

        Notice, that for this automated download, the "unzip" program
        must be installed and $::acs::rootdir/packages/www must be
        writable by the web server.

    } {
        set resource_info  [resource_info -version $version]
        set version        [dict get $resource_info configuredVersion]
        set resourceDir    [dict get $resource_info resourceDir]
        set versionSegment [::util::resources::version_segment -resource_info $resource_info]

        ::util::resources::download -resource_info $resource_info

        #
        # Do we have unzip installed?
        #
        set unzip [::util::which unzip]
        if {$unzip eq ""} {
            error "can't install Showdown locally; no unzip program found on PATH"
        }

        #
        # Do we have a writable output directory under resourceDir?
        #
        set path $resourceDir/$versionSegment
        if {![file isdirectory $path]} {
            file mkdir $path
        }
        if {![file writable $path]} {
            error "directory $path is not writable"
        }

        #
        # So far, everything is fine, unpack the editor package.
        #
        foreach url [dict get $resource_info downloadURLs] {
            set fn [file tail $url]
            util::unzip -overwrite -source $path/$fn -destination $path
        }

        foreach f [glob \
                       $path/showdownjs-*/dist/*.* \
                      ] {
            file rename $f $path/[file tail $f]
        }
    }

}

# Local variables:
#    mode: tcl
#    tcl-indent-level: 4
#    indent-tabs-mode: nil
# End:
