#!/bin/bash

# Copyright 2014 The Kubernetes Authors All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# The business logic for whether a given object should be created
# was already enforced by salt, and /etc/kubernetes/addons is the
# managed result is of that. Start everything below that directory.

# Parameters
# $1 path to add-ons


# LIMITATIONS
# 1. controllers are not updated unless their name is changed
# 2. Services are treated as controllers, i.e. they will be udpated
#    if service name is changed. the suffix after the last '-' is
#    treated as verson. But we don't name services like this.
# 3. Services will not be updated unless thir name is changed,
#    but for services we acually want updates without name change.
# 4. Json files are not handled at all. Currently addons must be
#    in yaml files
# 5. exit code is prabably not always correct (I haven't checked
#    carefully if it works in 100% cases)
# 6. There are no unittests
# 7. object kind is checked using 'grep' it's possible that it doesn't work in
#    all cases
# 8. Will not work if the total length of paths to addons is greater than
#    bash can handle. Probably it is not a problem: ARG_MAX=2097152 on GCE.
#

# cosmetic improvements to be done
# 1. improve the log function; add timestamp, file name, etc.
# 2. logging doesn't work from files that print things out.
# 3. kubectl prints the output to stderr (the output should be captured and then
#    logged)



# global config
KUBECTL=${TEST_KUBECTL:-/usr/local/bin/kubectl}   # substitute for tests
NUM_TRIES_FOR_CREATE=${TEST_NUM_TRIES:-100}
DELAY_AFTER_CREATE_ERROR_SEC=${TEST_DELAY_AFTER_ERROR_SEC:=10}
NUM_TRIES_FOR_STOP=${TEST_NUM_TRIES:-100}
DELAY_AFTER_STOP_ERROR_SEC=${TEST_DELAY_AFTER_ERROR_SEC:=10}

if [[ ! -f $KUBECTL ]]; then
    echo "ERROR: kubectl command ($KUBECTL) not found or is not executable" 1>&2
    exit 1
fi


# remember that you can't log from functions that print some output (because
# logs are also printed on stdout)
# $1 level
# $2 message
function log() {
  # manage log levels manually here

  # add the timestamp if you find it useful
  case $1 in
    DB3 )
#        echo "$1: $2"
        ;;
    DB2 )
#        echo "$1: $2"
        ;;
    DBG )
#        echo "$1: $2"
        ;;
    INFO )
        echo "$1: $2"
        ;;
    WRN )
        echo "$1: $2"
        ;;
    ERR )
        echo "$1: $2"
        ;;
    * )
        echo "INVALID_LOG_LEVEL $1: $2"
        ;;
  esac
}



# $1 addon path
# $2 addon type (e.g. ReplicationController)
# echoes the string with paths to files containing addon for the given type
# works only for yaml files (!) (ignores json files)
function get-addons-from-disk() {
    # prints to stdout, so log cannot be used
    local -r addon_path=$1
    local -r obj_type=$2

    for filePath in $(find $addon_path -name \*.yaml); do
        # WARNING: assumption that the topmost indentation is zero (I'm not sure yaml allows for topmost indentation)
        cat "${filePath}" | grep "^kind: ${obj_type}" >/dev/null 2>/dev/null 
        if [[ $? -eq 0 ]]; then
            echo $filePath
        fi
    done
}

# $1 file path
function get-object-name-from-file() {
    # prints to stdout, so log cannot be used
    #WARNING: only yaml is supported
    local -r name=$(cat $1 | python -c '''
try:
            import pipes,sys,yaml
            y = yaml.load(sys.stdin)
            print y["metadata"]["name"]
except Exception, ex:
            print "ERROR: %s" % ex
        ''')
    echo "${name}"
}

# waits for all subprocesses
# returns 0 if all of them were successful and 1 otherwise
function wait-for-jobs() {
    local rv=0
    for pid in $(jobs -p); do
        wait ${pid} || (rv=1; log ERR "error in pid ${pid}")
        log DB2 "pid ${pid} completed, current error code: $rv"
    done
    return $rv
}


function run-until-success() {
    local -r command=$1;
    local tries=$2;
    local -r delay=$3;
    local -r command_name=$1;
    while [ ${tries} -gt 0 ]; do
        log DBG "executing: '$command'"
        # let's give the command as an argument to bash -c, so that we can use
        # && and || inside the command itself
        /bin/bash -c "$command" && \
            log DB3 "== Successfully executed ${command_name} at $(date -Is) ==" && \
            return 0;
        let tries=tries-1;
        log INFO "== Failed to execute ${command_name} at $(date -Is). ${tries} tries remaining. =="
        sleep ${delay};
    done
    return 1;
}

# $1 object type
function get-addons-from-server() {
    local -r obj_type=$1
    "${KUBECTL}" get "$obj_type" -o template -t "{{range.items}}{{.metadata.name}} {{end}}" --api-version=v1beta3 -l kubernetes.io/cluster-service=true
}

# returns the characters after the last '-' (without it)
# $1 input string
function get-suffix() {
    # prints to stdout, so log cannot be used
    local input_string=$1
    # this will get the last field
    echo "$input_string" | rev | cut -d "-" -f1 | rev
}

# returns the characters up to the last '-' (without it)
# $1 input string
function get-basename() {
    # prints to stdout, so log cannot be used
    local -r input_string=$1
    local suffix=`get-suffix $input_string`
    suffix="-${suffix}"
    # this will strip the suffix (if matches)
    echo ${input_string%$suffix}
}

function stop-object() {
    local -r obj_type=$1
    local -r obj_name=$2
    log INFO "Stopping $obj_type $obj_name"
    run-until-success "${KUBECTL} stop ${obj_type} ${obj_name}" $NUM_TRIES_FOR_STOP $DELAY_AFTER_STOP_ERROR_SEC
}

function create-object() {
    local -r obj_type=$1
    local -r file_path=$2
    log INFO "Creating new $obj_type from file $file"
    run-until-success "${KUBECTL} create -f ${file_path}" $NUM_TRIES_FOR_CREATE $DELAY_AFTER_CREATE_ERROR_SEC
}

function update-object() {
    local -r obj_type=$1
    local -r obj_name=$2
    local -r file_path=$3
    log INFO "updating the $obj_type $obj_name with the new definition $file_path"
    stop-object $obj_type $obj_name
    create-object $obj_type $file_path
}

# deletes the objects from the server
# $1 object type
# $2 a list of object names
function stop-objects() {
    local -r obj_type=$1
    local -r obj_names=$2
    for obj_name in $obj_names; do
        stop-object $obj_type $obj_names &
    done
}

# creates objects from the given files
# $1 object type
# $2 a list of paths to definition files
function create-objects() {
    local -r obj_type=$1
    local -r file_paths=$2
    for file_path in $file_paths; do
        create-object $obj_type $file_path &
    done
}

# updates objects
# $1 object type
# $2 a list of update specifications
# each update specification is a `;` separated pair: <object name>;<file path>
function update-objects() {
    local -r obj_type=$1      # ignored
    local -r update_spec=$2
    for objdesc in $update_spec; do
        IFS=';' read -a array <<< $objdesc
        update-object $obj_type ${array[0]} ${array[1]} &
    done
}

# Global variables set by function match-objects.
for_delete=""       # a list of object names to be deleted
for_update=""      # a list of pairs <obj_name>;<filePath> for objects that should be updated
for_ignore=""       # a list of object nanes that can be ignored
new_files=""        # a list of file paths that weren't matched by any existing objects (these objects must be created now)


# $1 path to files with objects
# $2 object type in the API (ReplicationController or Service
function match-objects() {
    local -r addon_path=$1
    local -r obj_type=$2

    # output variables (globals)
    for_delete=""
    for_update=""
    for_ignore=""
    new_files=""

    onServer=`get-addons-from-server "$obj_type"`
    in_files=`get-addons-from-disk "$addon_path" "$obj_type"`

    log DB2 "onServer=$onServer"
    log DB2 "in_files=$in_files"

    local matched_files=""
    local name_from_file=""

    for obj_on_server in $onServer; do
        objBasename=`get-basename $obj_on_server`
        suffix=`get-suffix $obj_on_server`
        log DB3 "Found existing addon $obj_on_server, basename=$objBasename"

        # check if the addon is present in the directory and decide
        # what to do with it
        found=0
        for obj in $in_files; do
            name_from_file=`get-object-name-from-file $obj`
            if [[ "$name_from_file" == "ERROR" ]]; then
                log INFO "Cannot read object name from $obj. Ignoring"
                continue
            else
                log DB2 "Found object name '$name_from_file' in file $obj"
            fi
            new_suffix=`get-suffix $name_from_file`
            new_suffix="${new_suffix}"
            log DB3 "matching: ${objBasename}-${new_suffix} == ${name_from_file}"
            if [[ "${objBasename}-${new_suffix}" == "${name_from_file}" ]]; then
                log DB3 "matched existing replication controller $obj_on_server to file $obj; suffix=$suffix, new_suffix=$new_suffix"
                if [[ "$suffix" == "$new_suffix" ]]; then
                    for_ignore="$for_ignore $name_from_file"
                    matched_files="$matched_files $obj"
                    found=1
                    break
                else
                    for_update="$for_update $obj_on_server;$obj"
                    matched_files="$matched_files $obj"
                    found=1
                    break
                fi
            fi
        done
        if [[ $found  == 0 ]]; then
            log DB2 "No definition file found for replication controller $obj_on_server. Scheduling for deletion"
            for_delete="$for_delete $obj_on_server"
        fi
    done


    for obj in  $in_files; do
        echo $matched_files | grep $obj >/dev/null
        if [[ $? -ne 0 ]]; then
            new_files="$new_files $obj"
        fi
    done
}


function reconcile-objects() {
    local -r addon_path=$1
    local -r obj_type=$2
    match-objects $addon_path $obj_type

    log DBG "$obj_type: for_delete=$for_delete"
    log DBG "$obj_type: for_update=$for_update"
    log DBG "$obj_type: for_ignore=$for_ignore"
    log DBG "$obj_type: new_files=$new_files"

    stop-objects "$obj_type" "$for_delete"
    # wait for jobs below is a protection against changing the basename
    # of a replication controllerm without changing the selector.
    # If we don't wait, the new rc may be created before the old one is deleted
    # In such case the old one will wait for all its pods to be gone, but the pods
    # are created by the new replication controller. 
    # passing --cascade=false could solve the problem, but we want 
    # all orphan pods to be deleted.
    wait-for-jobs
    stopResult=$?

    create-objects "$obj_type" "$new_files"
    update-objects "$obj_type" "$for_update"

    for obj in $for_ignore; do
        log DB2 "The $obj_type $obj is already up to date"
    done

    wait-for-jobs
    createUpdateResult=$?

    if [[ $stopResult == 0 ]] && [[ $createUpdateResult == 0 ]]; then
        return 0
    else
        return 1
    fi
}

function update-addons() {
    local -r addon_path=$1
    # be careful, reconcile-objects uses global variables
    reconcile-objects $addon_path ReplicationController &

    # Warning, we don't expect service names to be versioned, so
    # the update for services should be turned off - just new services
    # should be created and the old ones should be gone
    # Also, if service description differs, the service should be recreated
    # regardless of its name. This is not implemented in this version.
    reconcile-objects $addon_path Service &

    wait-for-jobs
    if [ $? == 0 ]; then
        log INFO "== Kubernetes addon upgrade completed successfully at $(date -Is) =="
    else
        log WRN "== Kubernetes addon upgrader completed with errors at $(date -Is) =="
    fi
}

if [ "$#" -ne 1 ]; then
    echo "Illegal number of parameters" 1>&2
    exit 1
fi

addon_path=$1
update-addons $addon_path

