# -*- mode:shell-script;coding:utf-8 -*-
####
#### bash functions to run tests on iOS devices and simulators.
####
set +o posix

function exitIfScript(){
    local status="${1-$?}"
    case $- in
        (*i*) return "$status" ;;
        (*)   exit   "$status" ;;
    esac
}
if [[ ${bashUtil_PROVIDED:-false} = false ]] ; then
    if [ -z "${COMP_PATH_Scripts-}" ] ; then
        cd "${BASH_SOURCE%/*}/../../../../../../build/tools/Scripts" >/dev/null || exitIfScript $?
        COMP_PATH_Scripts="$(pwd -P)"
        cd - >/dev/null
    fi
    source "${COMP_PATH_Scripts}/bashUtil.sh"
fi

require os iosSim iosReal

function ios-help(){
    # Usage: ios-help
    sed -n -e 's/[#] Usage: //p' "${BASH_SOURCE[0]}"
}

function ios-device-kind(){
    # Usage: ios-device-kind $deviceUDID --> kind
    local deviceUDID="$1"
    case "$deviceUDID" in
        (*-*) echo sim ;;
        (*)  echo real ;;
    esac
}


function ios-list-devices(){
    # Usage: ios-list-devices --> { kind deviceUDID sdkVersion deviceName }
    instruments -s devices 2>/dev/null \
        |sed -n -E \
             -e 's/^(.*) \(([0-9.]+)\) \[([-0-9A-Fa-f]+)\]$/kind=real;udid="\3";sdk="\2";name="\1"/p' \
             -e 's/^(.*) \(([0-9.]+)\) \[([-0-9A-Fa-f]+)\] \(Simulator\)$/kind=sim;udid="\3";sdk="\2";name="\1"/p' \
        | while read record ; do
        eval "$record"
        printf "%-4s %-40s %-10s %s\n" "$kind" "$udid" "$sdk" "$name"
    done
}


function ios-list-devices-2(){
    # Usage: ios-list-devices --> { kind deviceUDID sdkVersion deviceName }
    local tmp="$(mktemp)"
    instruments -s devices 2>/dev/null > "$tmp"
    sed -n -E \
        -e 's/^(.*) \(([0-9.]+)\) \[([-0-9A-Fa-f]+)\]$/kind=real;udid="\3";sdk="\2";name="\1"/p' \
        <"$tmp" >"${tmp}.real"
    sed -n -E \
        -e 's/^(.*) \(([0-9.]+)\) \[([-0-9A-Fa-f]+)\] \(Simulator\)$/\3/p' \
        <"$tmp" >"${tmp}.sim"
    while read record ; do
        eval "$record"
        printf "%-4s %-40s %-10s %s\n" "$kind" "$udid" "$sdk" "$name"
    done < "${tmp}.real"
    sim-list-devices | grep -Ff "${tmp}.sim"
}




function ios-list-applications(){
    # Usage: ios-list-applications --> { deviceUDID applicationID }
    real-list-applications
    sim-list-applications
}

function ios-device-install-application(){
    # Usage: ios-device-install-application $deviceUDID $applicationPackage
    local deviceUDID="$1"
    local applicationPackage="$2"
    local kind=$(ios-device-kind "$deviceUDID")
    ${kind}-device-install-application "$deviceUDID" "$applicationPackage"
}

function ios-device-run-application(){
    # Usage: ios-device-run-application $deviceUDID $applicationID
    # Launch the application and waits until it exits.
    local deviceUDID="$1"
    local applicationID="$2"
    local kind=$(ios-device-kind "$deviceUDID")
    ${kind}-device-run-application "$deviceUDID" "$applicationID"
}

function ios-device-fetch-application-container(){
    # Usage: ios-device-fetch-application-container $deviceUDID $applicationID
    # Prints the path of the application sandbox tarball (where the executable and resources are stored).
    local deviceUDID="$1"
    local applicationID="$2"
    local kind=$(ios-device-kind "$deviceUDID")
    ${kind}-device-fetch-application-container "$deviceUDID" "$applicationID"
}

function ios-device-fetch-application-sandbox(){
    # Usage: ios-device-fetch-application-sandbox $deviceUDID $applicationID
    # Prints the path of the application sandbox tarball (where the executable and resources are stored).
    local deviceUDID="$1"
    local applicationID="$2"
    local kind=$(ios-device-kind "$deviceUDID")
    ${kind}-device-fetch-application-sandbox "$deviceUDID" "$applicationID"
}


function ios-run-application(){
    # Usage: ios-run-application $deviceUDID $applicationPackage
    local deviceUDID="$1"
    local applicationPackage="$2"
    local kind=$(ios-device-kind "$deviceUDID")
    ${kind}-run-application "$deviceUDID" "$applicationPackage"
}

function ios-debug-application(){
    # Usage: ios-debug-application $deviceUDID $applicationPackage
    local deviceUDID="$1"
    local applicationPackage="$2"
    local kind=$(ios-device-kind "$deviceUDID")
    ${kind}-run-application "$deviceUDID" "$applicationPackage" debug
}
