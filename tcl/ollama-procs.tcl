ad_library {

    Tcl wrapper to the Ollama REST API

}

namespace eval ollama {

    nx::Class create API {

        :property {host}
        :property {model ""}
        :property {timeout 3600}

        :method init {} {
            set :package_id [apm_package_id_from_key ollama]
            if {![info exists :host]} {
                set :host [parameter::get \
                               -package_id ${:package_id} \
                               -parameter ollama_host]
            }
        }

        :public method model {} {
            if {${:model} eq ""} {
                set :model [::parameter::get \
                                -package_id ${:package_id} \
                                -parameter default_generation_model]
            }
            return ${:model}
        }

        :method to_json {
            {vars {}}
        } {
            #
            # Transforms parameters into JSON, as needed in many api
            # endpoints.
            #
            # @param vars a list of vars defined in the caller scope. By
            #        default, all vars will be treated as JSON string
            #        values and automatically quoted. One can specify the
            #        modifiers :literal to not apply any quoting, :boolean
            #        to coalesce the value as either true or false,
            #        :array, to specify the value should become a JSON
            #        array when serialized, or arraystring, where the
            #        array will also be quoted.
            #
            package require json::write

            set body [list]
            foreach var $vars {
                lassign [split $var :] varname modifier
                if {$modifier ni {"" "boolean" "literal" "array" "arraystring"}} {
                    error "Invalid modifier '$modifier'"
                }

                if {![:uplevel info exists $varname]} {
                    continue
                }

                set value [:uplevel set $varname]

                if {$modifier eq ""} {
                    lappend body $varname [::json::write string $value]
                } elseif {$modifier eq "array"} {
                    lappend body $varname [::json::write array {*}$value]
                } elseif {$modifier eq "arraystring"} {
                    lappend body $varname [::json::write array-strings {*}$value]
                } elseif {$modifier eq "boolean"} {
                    lappend body $varname [expr {$value ? true : false}]
                } else {
                    lappend body $varname $value
                }
            }

            return [::json::write object {*}$body]
        }

        :method post {
            -url:required
            {-body ""}
            {-files ""}
            {-handler ""}
        } {
            #
            # Shorthand for POST requests
            #

            set payload [::util::http::post_payload -files $files -body $body]
            set body [dict get $payload payload]
            set body_file [dict get $payload payload_file]
            set headers [ns_set array [dict get $payload headers]]

            package require http
            package require tls
            ::http::register https 443 ::tls::socket

            set cmd [list \
                         ::http::geturl ${:host}$url \
                         -headers $headers]
            if {$body_file ne ""} {
                set body_channel [open $body_file r]
                lappend cmd -querychannel $body_channel
            } else {
                lappend cmd -query $body
            }
            if {$handler ne ""} {
                lappend cmd -handler $handler
            }

            try {
                set response [array get [{*}$cmd]]
            } finally {
                if {[info exists body_channel]} {
                    close $body_channel
                }
            }

            return $response
        }

        :method images_to_base64 {
            images
        } {
            #
            # Transforms a list of absolute file paths into a list of
            # base64 strings representations of the files content.
            #
            return [lmap image $images {
                set rfd [open $image r]
                set bin [read $rfd]
                close $rfd
                ns_base64encode -binary -- $bin
            }]
        }

        :public method generate {
                                 -prompt
                                 -suffix
                                 -images
                                 -format
                                 -options
                                 -system
                                 -template
                                 -context
                                 {-handler ""}
                                 -raw
                                 -keep_alive
                             } {
            #
            # Generate a completion
            #
            # When not specified differently, every parameter has the
            # same format and behavior as in the corresponding api
            # endpoint.
            #
            # @param images the list of images is a list of absolute paths to
            #        files that will be automatically converted to base64.
            #
            # @see https://github.com/ollama/ollama/blob/main/docs/api.md#generate-a-completion
            #
            # @return endpoint response as dict
            #

            if {[info exists images]} {
                set images [:images_to_base64 $images]
            }

            set model [:model]

            set stream [expr {$handler ne ""}]

            set body [:to_json {
                model
                prompt
                stream:boolean
                raw:boolean
                images:arraystring
                suffix
                format
                options:literal
                system
                template
                context
                keep_alive
            }]

            return [:post \
                        -body $body \
                        -handler $handler \
                        -url /api/generate]
        }

        :public method load {} {
            #
            # Loads the model to speed up subsequent interactions.
            #
            return [:generate]
        }

        :public method unload {} {
            #
            # Unloads the model to free system resources.
            #
            return [:generate -keep_alive 0]
        }

        :public method chat {
                             -messages
                             -tools
                             -format
                             -options
                             {-handler ""}
                             -keep_alive
                         } {
            #
            # Generate a chat completion
            #
            # When not specified differently, every parameter has the
            # same format and behavior as in the corresponding api
            # endpoint.
            #
            # @param messages list of dicts with fields "role",
            #                 "content", "images" and
            #                 "tool_calls". "images" is a list of
            #                 absolute pahts to files on the
            #                 filesystem. "tool_calls" is currently
            #                 assumed to be a literal JSON object.
            #
            # @see https://github.com/ollama/ollama/blob/main/docs/api.md#generate-a-chat-completion
            #
            # @return endpoint response as dict
            #

            if {[info exists messages]} {
                set messages [lmap message $messages {
                    dict with message {
                        if {[info exists images]} {
                            set images [:images_to_base64 $images]
                        }
                        :to_json {
                            role
                            content
                            images:arraystring
                            tool_calls:array
                        }
                    }
                }]
            }

            set model [:model]

            set stream [expr {$handler ne ""}]

            set body [:to_json {
                model
                messages:array
                stream:boolean
                format
                options:literal
                system
                keep_alive
            }]

            return [:post \
                        -body $body \
                        -handler $handler \
                        -url /api/chat]

        }

        :public method create {
                               -model
                               -modelfile
                               {-handler ""}
                               -path
                               -quantize
                           } {
            #
            # Create a Model
            #
            # When not specified differently, every parameter has the
            # same format and behavior as in the corresponding api
            # endpoint.
            #
            # @see https://github.com/ollama/ollama/blob/main/docs/api.md#create-a-model
            #
            # @return endpoint response as dict
            #

            set stream [expr {$handler ne ""}]

            set body [:to_json {
                model
                modelfile
                stream:boolean
                path
                quantize
            }]

            return [:post \
                        -body $body \
                        -handler $handler \
                        -url /api/create]
        }

        :public method blobs {
                              -digest
                              -file
                          } {
            #
            # Check if a Blob Exists or create a new blob.
            #
            # When not specified differently, every parameter has the
            # same format and behavior as in the corresponding api
            # endpoint.
            #
            # @see https://github.com/ollama/ollama/blob/main/docs/api.md#check-if-a-blob-exists
            # @see https://github.com/ollama/ollama/blob/main/docs/api.md#create-a-blob
            #
            # @return endpoint response as dict
            #
            if {[info exists file]} {
                set files [list \
                               [list \
                                    "file" $file \
                                    "fieldname" "file"]]
                return [:post \
                            -files $files \
                            -url /api/blobs/sha256:[ns_md file -digest sha256 $file]]
            } else {
                return [ns_http run -method HEAD ${:host}/api/blobs/${digest}]
            }
        }

        :public method tags {} {
            #
            # List Local Models
            #
            # @see https://github.com/ollama/ollama/blob/main/docs/api.md#list-local-models
            #
            # @return endpoint response as dict
            #
            return [util::http::get -url ${:host}/api/tags]
        }

        :public method models {} {
            #
            # List installed models. This is a shorthand of the tags
            # method returning the pre-digested list from the API
            # response.
            #
            # @return list of model information
            #
            package require json
            return [dict get [::json::json2dict [dict get [:tags] page]] models]
        }

        :public method show {
                             -model:required
                             -verbose
                         } {
            #
            # Show Model Information
            #
            # @see https://github.com/ollama/ollama/blob/main/docs/api.md#list-local-models
            #
            # @return endpoint response as dict
            #
            set body [:to_json {
                model
                verbose:boolean
            }]

            return [:post \
                        -body $body \
                        -url /api/show]
        }

        :public method copy {
                             -source:required
                             -destination:required
                         } {
            #
            # Copy a Model
            #
            # @see https://github.com/ollama/ollama/blob/main/docs/api.md#copy-a-model
            #
            # @return endpoint response as dict
            #
            set body [:to_json {
                source
                destination
            }]

            return [:post \
                        -body $body \
                        -url /api/copy]
        }

        :public method delete {
                               -model:required
                           } {
            #
            # Delete a Model
            #
            # @see https://github.com/ollama/ollama/blob/main/docs/api.md#delete-a-model
            #
            # @return endpoint response as dict
            #
            set body [:to_json {
                model
            }]

            return [:post \
                        -body $body \
                        -url /api/delete]
        }

        :public method pull {
                             -model:required
                             -insecure
                             {-handler ""}
                         } {
            #
            # Pull a Model
            #
            # @see https://github.com/ollama/ollama/blob/main/docs/api.md#pull-a-model
            #
            # @return endpoint response as dict
            #

            set stream [expr {$handler ne ""}]

            set body [:to_json {
                model
                insecure:boolean
                stream:boolean
            }]

            return [:post \
                        -body $body \
                        -handler $handler \
                        -url /api/pull]
        }

        :public method push {
                             -model:required
                             -insecure
                             {-handler ""}
                         } {
            #
            # Push a Model (requires account)
            #
            # @see https://github.com/ollama/ollama/blob/main/docs/api.md#push-a-model
            #
            # @return endpoint response as dict
            #

            set stream [expr {$handler ne ""}]

            set body [:to_json {
                model
                insecure:boolean
                stream:boolean
            }]

            return [:post \
                        -body $body \
                        -handler $handler \
                        -url /api/push]
        }

        :public method embed {
                              -input:required
                              -truncate
                              -options
                              -keep_alive
                          } {
            #
            # Generate Embeddings
            #
            # @see https://github.com/ollama/ollama/blob/main/docs/api.md#generate-embeddings
            #
            # @return endpoint response as dict
            #
            set model [:model]

            set body [:to_json {
                model
                input:arraystring
                truncate:boolean
                options:literal
                keep_alive
            }]

            return [:post \
                        -body $body \
                        -url /api/embed]
        }

        :public method ps {} {
            #
            # List Running Models
            #
            # @see https://github.com/ollama/ollama/blob/main/docs/api.md#list-running-models
            #
            # @return endpoint response as dict
            #
            return [util::http::get -url ${:host}/api/ps]
        }

    }

}

#
# Local variables:
#    mode: tcl
#    tcl-indent-level: 2
#    indent-tabs-mode: nil
# End
