# -*- mode:shell-script;coding:utf-8 -*-
####
#### bash functions to manage iOS simulators.
####
set +o posix
if [[ ${bashUtil_PROVIDED:-false} = false ]] ; then
    if [ -z "${COMP_PATH_Scripts-}" ] ; then
        cd "${BASH_SOURCE%/*}/../../../../../../build/tools/Scripts" || exitIfScript $?
        COMP_PATH_Scripts="$(pwd -P)"
        cd -
    fi
    source "${COMP_PATH_Scripts}/bashUtil.sh"
fi
require json iosCommands

# Parameters:
#
# CONTAINER_DIR         The directory where the container and sandbox tarballs are saved.
#
# SIM_TRACE             0 or 1, default 0, whether to print debugging variables.
# SIM_VERBOSE           0 or 1, default 1, whether to print messages and progress.
#
# SIMULATOR_NAME        The AppleScript name of the Simulator.app application.
# SIMULATOR_PACKAGE     The path to the Simulator.app application.
# SIMULATOR_EXECUTABLE  (optional) The path to the Simulator.app executable.
#
#
# The main entry point is:
#
#    sim-run-application $deviceTypeID $simRuntimeID $applicationPackage
#
# when the application terminates, its container and sandbox are tarballed into $CONTAINER_DIR.
#
# sim-help gives the list of functions with their parameters.
#
# for type in $(sim-device-types) ; do
#     for sdk in $(sim-ios-runtime-versions) ; do
#         sim-run-application $type $sdk $applicationPackage
#     done
# done
#
# will test the application in all combinations of simulated device types and sdk versions.

CONTAINER_DIR="${CONTAINER_DIR:-/tmp}"

SIM_TRACE=${SIM_TRACE:-0}
SIM_VERBOSE=${SIM_VERBOSE:-1}

SIMULATOR_NAME="${SIMULATOR_NAME:-Simulator}"
SIMULATOR_PACKAGE="${SIMULATOR_PACKAGE:-/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app}"
SIMULATOR_EXECUTABLE="${SIMULATOR_EXECUTABLE:-${SIMULATOR_PACKAGE}/Contents/MacOS/Simulator}"



# $ sim-device-types|head -2
# com.apple.CoreSimulator.SimDeviceType.iPhone-4s
# com.apple.CoreSimulator.SimDeviceType.iPhone-5
#
# $ sim-device-type-name com.apple.CoreSimulator.SimDeviceType.iPhone-4s
# iPhone 4s
#
# $ sim-device-type-id 'iPhone 4s'
# com.apple.CoreSimulator.SimDeviceType.iPhone-4s
#
# $ sim-ios-runtime-versions|head -2
# com.apple.CoreSimulator.SimRuntime.iOS-8-1
# com.apple.CoreSimulator.SimRuntime.iOS-8-2
#
# $ sim-runtime-name com.apple.CoreSimulator.SimRuntime.iOS-8-1
# iOS 8.1
#
# $ sim-runtime-id 'iOS 8.1'
# com.apple.CoreSimulator.SimRuntime.iOS-8-1

function sim-printf(){
    if [[ "$SIM_VERBOSE" -ne 0 ]] ; then
        printf "$@"
    fi
}


function sim-errorf(){
    (
        printf '\n\nERROR: '
        printf "$@"
        printf '\n\n'
    ) >&2
    return 1
}


#
# NOTE: the device name in simctl list, is initialized by default to a
#       name corresponding to the device type id (device name).  but
#       this is not a device type name field, as demonstrated when we
#       create a device:
#
#            simctl create $name $deviceTypeID $simRuntimeID
#
#       Apparently, there's no way to get back the device name or
#       device type ID from a device created with a different name
#       (but the simulator can stil launch it with the right device
#       type).
#

function sim-help(){
    # Usage: sim-help
    sed -n -e 's/[#] Usage: //p' "${BASH_SOURCE[0]}"
}

function sim-device-types(){
    # Usage: sim-device-types --> { deviceTypeID }
    xcrun simctl list devicetypes|sed -n -e '/iPad\|iPhone/s/.*(\([^)]*\)).*/\1/p'
}

function sim-device-type-name(){
    # Usage: sim-device-type-name $deviceTypeID --> deviceTypeName
    local deviceTypeID="$1"
    xcrun simctl list devicetypes|sed -n '/('"${deviceTypeID}"')/s/ (.*//p'
}

function sim-device-type-id(){
    # Usage: sim-device-type-id $deviceTypeName --> deviceTypeID
    local deviceTypeName="$1"
    xcrun simctl list devicetypes|sed -n 's/^'"${deviceTypeName}"' (\([^)]*\))$/\1/p'
}

function sim-ios-runtime-versions(){
    # Usage: sim-ios-runtime-versions --> { simRuntimeID }
    xcrun simctl list runtimes|sed -n -e '/iOS/s/.*(\([^)]*\)).*/\1/p'
}

function sim-runtime-name(){
    # Usage: sim-runtime-name $simRuntimeID -> simRuntimeName
    local runtimeID="$1"
    xcrun simctl list runtimes|sed -n 's/^\([^(]*\) (\([^)]*\)) ('"${runtimeID}"')$/\1/p'
}

function sim-runtime-id(){
    # Usage: sim-runtime-id $simRuntimeName -> simRuntimeID
    local runtimeName="$1"
    xcrun simctl list runtimes|sed -n 's/^'"${runtimeName}"' (\([^)]*\)) (\([^)]*\))$/\2/p'
}

runtimeNameString=nil
stateString=nil
availabilityString=nil
nameString=nil
udidString=nil
devicesString=nil

function sim-initStrings(){
    if [[ ${nameString:-nil}  = nil ]] ; then
        for str in devices runtimeName state availability name udid ; do
            make-string $str;eval ${str}String=\$top;pop
        done
    fi
}

runtimeName=nil
function adjoin-runtime-name(){
    # deviceRecord -- (cons (cons "runtimeName" $runtimeName) deviceRecord)
    if [[ $runtimeNameString = nil ]] ; then
        sim-initStrings
    fi
    push $runtimeNameString;make-string "$runtimeName";cons
    swap;cons
}

function sim-all-devices(){
    # Synopsis:  -- devicesRef
    # Usage: sim-all-devices;prin1;terpri
    parse-json "$(xcrun simctl list devices -j)"
    sim-initStrings
    push $devicesString ; assoc ; cdr
    local result=nil
    while [[ $top != nil ]] ; do
        dup;cdr;swap;car                                   # -- (cdr runtimelist) (car runtimelist)
        dup;cdr;swap;car                                   # -- (cdr runtimelist) (cdr (car runtimelist)) (car (car runtimelist))
        cell-value $top;runtimeName="$cell_value";pop     # -- (cdr runtimelist) runtimeDevices
        mapcar adjoin-runtime-name                        # -- (cdr runtimelist) runtimeDevices'
        push $result;nconc;result=$top;pop
    done
    push $result
}

function sim-not-bootedp(){
    # string -- bootedp # whether the string is equal to "Booted"
    cell-value $top
    if [[ "$cell_value" == Booted ]] ; then
        pop;push nil
    fi
}

function sim-get-device-state(){
    # deviceRecord -- state
    if [[ $stateString = nil ]] ; then
        sim-initStrings
    fi
    push $stateString;assoc;cdr
}

function sim-print-device(){
    # deviceRecord -- deviceRecord
    local -a slots=(udid state availability runtimeName name)
    local -a format=('%-36s' '%-8s' '%-11s' '%-11s' '%s')
    sim-initStrings
    for (( i=0 ; i<=${#slots} ; i++ )) ; do
        dup;eval push \${${slots[$i]}String};assoc;cdr;cell-value $top;pop
        sim-printf "${format[$i]}  " "$cell_value"
    done
    sim-printf '\n'
}


function sim-booted-devices(){
    # -- booted_device_list
    sim-all-devices;remove-if sim-not-bootedp sim-get-device-state
}

function sim-list-devices(){
    # Usage: sim-list-devices
    # TODO: This is slow (the first time, or when the list changes),
    #       since it parses json output in bash (but we've already divided
    #       by 3 the parsing time in json.sh, so it's not too slow).
    # TODO: We should incorporate this into siminfo (or improve json parsing speed in bash).
    local cmd
    if [[ $# -ge 1 ]] ; then
        case "$1" in
            booted) cmd=sim-booted-devices ;;
            all)    cmd=sim-all-devices    ;;
            *)      sim-errorf 'Invalid selection %s; choose one of: booted all' "${1}" ;;
        esac
    else
        cmd=sim-all-devices
    fi
    $cmd;mapcar sim-print-device;pop
}

function sim-list-applications(){
    # Usage: sim-list-applications
    siminfo --list-devices | while read deviceUDID ; do
        siminfo --list-applications $deviceUDID | while read applicationID ; do
            IFS=^ ai=( $(siminfo --application-info $deviceUDID $applicationID|tr '\012' '^') )
            sim-printf '%-36s %-30s %-16s %-11s\n\t%s\n\t%s\n' "$deviceUDID" "$applicationID" "${ai[@]}"
        done
    done
}

function sim-device(){
    # Usage: sim-device $udid --> $deviceRecordRef
    # Usage: sim-device $udid;prin1;terpri
    local deviceID="$1"
    parse-json "$(xcrun simctl list devices -j)"
    sim-initStrings
    push $devicesString ; assoc ; cdr # -- runtimelist
    while [[ $top != nil ]] ; do
        dup;cdr;swap;car                                   # -- (cdr runtimelist) (car runtimelist)
        dup;cdr;swap;car                                   # -- (cdr runtimelist) (cdr (car runtimelist)) (car (car runtimelist))
        cell-value $top;simRuntimeName="$cell_value";pop  # -- (cdr runtimelist) runtimeDevices
        while [[ $top != nil ]] ; do
            dup;cdr;swap;car                               # -- (cdr runtimelist) (cdr runtimeDevices) deviceRecord
            dup;push $udidString;assoc;cdr                # -- (cdr runtimelist) (cdr runtimeDevices) deviceRecord udid
            if [[ $top = nil ]] ; then
                # no name slot!
                pop;pop                                   # -- (cdr runtimelist) (cdr runtimeDevices)
            else
                cell-value $top
                if [[ "$cell_value" = "$deviceID" ]] ; then
                    pop                                   # -- (cdr runtimelist) (cdr runtimeDevices) deviceRecord
                    swap;pop;swap;pop                       # -- deviceRecord
                    break 2
                else
                    pop;pop
                fi
            fi
        done
    done
}

function sim-find-device-by-deviceTypeName-and-runtimeName(){
    # Usage: sim-find-device-by-deviceTypeName-and-runtimeName "$deviceTypeName" "$simRuntimeName" --> UDID
    local deviceTypeName="$1"
    local simRuntimeName="$2"
    local udid=''
    local state=''
    local availability=''
    parse-json "$(xcrun simctl list devices -j)"
    sim-initStrings
    push $devicesString ; assoc ; cdr
    #DEBUG# echo -n '# devices: ';dup;length;prin1;terpri
    make-string "$simRuntimeName" ; assoc ; cdr
    #DEBUG# echo -n '# runtime: ';dup;length;prin1;terpri
    while [[ $top != nil ]] ; do
        dup;cdr;swap;car                # -- (cdr runtimelist) (car runtimelist)
        #DEBUG# echo -n 'current device: ';dup;prin1;terpri
        dup;push $nameString;assoc;cdr # -- (cdr runtimelist) (car runtimelist) name
        #DEBUG# echo -n 'current device name: ';dup;prin1;terpri
        if [[ $top = nil ]] ; then
            # no name slot!
            pop;pop
        else
            cell-value $top
            if [[ "$cell_value" = "$deviceTypeName" ]] ; then
                pop
                dup;push $udidString;         assoc;cdr;cell-value $top;udid=$cell_value;         pop  # -- (cdr runtimelist) (car runtimelist)
                dup;push $availabilityString; assoc;cdr;cell-value $top;availability=$cell_value; pop
                dup;push $stateString;        assoc;cdr;cell-value $top;state=$cell_value;        pop
                pop;pop
                break
            else
                pop;pop
            fi
        fi
    done
    # push $availability
    # push $state
    echo $udid
}

function sim-find-device(){
    # Usage: sim-find-device $deviceTypeIdOrName $simRuntimeIdOrName -> deviceID
    local deviceTypeID="$1"
    local simRuntimeID="$2"
    local deviceTypeName="$(sim-device-type-name "$deviceTypeID")"
    local simRuntimeName="$(sim-runtime-name "$simRuntimeID")"
    deviceTypeName="${deviceTypeName:-$deviceTypeID}"
    simRuntimeName="${simRuntimeName:-$simRuntimeID}"
    sim-find-device-by-deviceTypeName-and-runtimeName "$deviceTypeName" "$simRuntimeName"
}


function sim-create-device(){
    # Usage: sim-create-device $name $deviceTypeID $simRuntimeID --> deviceID
    local name="$1"
    local deviceType="$2"
    local simRuntime="$3"
    xcrun simctl create "$name" "$deviceType" "$simRuntime"
}

function sim-delete-device(){
    # Usage: sim-delete-device $deviceID
    local deviceID="$1"
    xcrun simctl delete "$deviceID"
}

function pids(){ ps ax|awk '{print $1}'|sort -n ; }


function sim-device-state(){
    local deviceUDID="$1"
    xcrun simctl list|grep "$deviceUDID"
}

function ios-applicationID-from-package(){
    # Usage: ios-applicationID-from-package $applicationPackage --> applicationID
    local applicationPackage="$1"
    defaults read  "${applicationPackage}/Info.plist" CFBundleIdentifier
    # Alternative:
    # plutil -extract CFBundleIdentifier xml1 -o -  "${applicationPackage}/Info.plist" | plutil -p -
}




function sim-device-install-application(){
    # Usage: sim-device-install-application $deviceUDID $applicationPackage
    local deviceUDID="$1"
    local applicationPackage="$2"
    local applicationID=$(ios-applicationID-from-package "$applicationPackage")
    local bigtries=4
    local tries=4
    local status=0
    local bundle=""
    sim-printf '# Install the application %s.\n'  "$applicationPackage"
    # a race condition / timing bug in SpringBoard, so if this doesn't work, we shall try again.
    while [[ $tries -ge 0 ]] ; do
        xcrun simctl install  "$deviceUDID" "$applicationPackage" ; status=$?
        bundle="$(siminfo -ab "$deviceUDID" "$applicationID")"
        if [[ -d "$bundle" ]] ; then
            sim-printf '# Installed %s\n' "$applicationID"
            # sim-device-reboot "$deviceUDID"
            return 0
        else
            sim-printf '# Let us try again.\n'
            sleep 1
        fi
        # check we're installed…
        tries=$((tries-1))
    done
    sim-errorf 'Could not install the application.'
    if [[ $status -eq 0 ]] ; then
        return 1
    else
        return $status
    fi
}

function sim-progress-wait(){
    # Usage: sim-progress-wait $duration [$inverval]
    # Wait for $duration seconds, printing dots at $interval seconds; finally print a newline.
    local duration="$1"
    local interval="$2"
    interval=${interval:-1}
    while [[ $duration -ge 0 ]] ; do
        sim-printf '.' ; sleep "$interval" ; duration=$((duration-interval))
    done
    sim-printf '\n'
}


function sim-wait-process(){
    # Usage: sim-wait-process $pid [$progressPeriod]
    # Wait until the process dies.
    local pid="$1"
    local progress="$2"
    local i=0
    progress="${progress:-0}"
    while ps -p "$pid" > /dev/null ; do
        sleep 1
        i=$((i+1))
        if [[ "$progress" -ne 0 ]] ; then
            if [[ "$progress" -le "$i" ]] ; then
                sim-printf '.'
                i=0
            fi
        fi
    done
    if [[ "$progress" -ne 0 ]] ; then
        sim-printf '\n'
    fi
}

function sim-wait-for-process-named(){
    # Usage: sim-wait-for-process-named $processName
    # Wait until a new process with the command $processName exists.
    local name="$1"
    local tmp="$(mktemp)"
    local tmp1="${tmp}.1"
    local tmp2="${tmp}.2"
    ps axlww>"${tmp1}"
    while sleep 1 ; do
        ps axlww>"${tmp2}"
        diff "${tmp1}" "${tmp2}"|grep -q -s -e "^> .*${name}" && break
    done
    diff  "${tmp1}" "${tmp2}"|awk "/^> .*${name//\//\/}/"'{print $3}'
    rm "${tmp2}" "${tmp1}"
}

function sim-expected-process-for-device(){
    # Usage: sim-expected-process-for-device $deviceUDID
    # This prints the name of one of the latest processes that will be
    # launched by the simulator in the version run by the device.
    local deviceUDID="$1"
    local runtimeVersion=$(siminfo -ds $deviceUDID)
    case "$runtimeVersion" in
        *8.[01]*) echo MobileCal           ;;
        *)        echo nanoregistrylaunchd ;;
    esac
}


function sim-device-boot(){
    # Usage: sim-device-boot $deviceUDID;simPID=$top;pop
    # -- simPID
    # Boots the device and the simulator GUI.
    local deviceUDID="$1"
    local expectedProcess="$(sim-expected-process-for-device "$deviceUDID")"
    local pidfile="$(mktemp)"
    local simpid=""
    local getpidprocess
    # Running (xcrun simctl boot $deviceUDID) alone doesn't allow one to launch an application, since the GUI is missing.
    # We need to launch the GUI ${SIMULATOR_PACKAGE}, which will call (xcrun simctl boot $deviceUDID).
    sim-printf '# Booting the new device %s.\n' "$deviceUDID"
    sim-wait-for-process-named "${SIMULATOR_PACKAGE}.*-CurrentDeviceUDID *${deviceUDID}" > "${pidfile}" & getpidprocess=$!
    open -n "$SIMULATOR_PACKAGE" --args -CurrentDeviceUDID "$deviceUDID"
    wait "$getpidprocess" && simpid="$(cat "$pidfile")" || simpid=""
    sim-printf '# Wait for "Booted" state.'
    sim-wait-for-process-named "$expectedProcess" > /dev/null
    until xcrun simctl list | grep -q -s "${name} (${deviceUDID}) (Booted)" ; do
        sim-printf '.' ; sleep 1
    done ; sim-printf '\n'
    # still wait a few seconds for the things to start up…
    sim-printf '# ';sim-progress-wait 6 1
    sim-printf '# Simulator pid = %s\n' $simpid
    push $simpid
}


function sim-device-shutdown(){
    # Usage: sim-device-shutdown $deviceUDID $simPID
    local deviceUDID="$1"
    local simpid="$2"
    sim-printf '# Shut down the device %s.\n' "$deviceUDID"
    xcrun simctl shutdown "$deviceUDID"
    sleep 1
    sim-printf '# Kill the simulator pid %d.\n' "$simpid"
    kill $simpid
}

function sim-device-reboot(){
    # Usage: sim-device-reboot #deviceUDID
    # This doesn't touch the simulator application, only the iOS device simulator processes
    local deviceUDID="$1"
    sim-printf '# Rebooting:\n'
    sim-printf '#   Shut down the device %s.\n' "$deviceUDID"
    xcrun simctl shutdown "$deviceUDID"
    sleep 1
    sim-printf '#   Booting the new device %s.\n' "$deviceUDID"
    xcrun simctl boot "$deviceUDID"
    sim-printf '#   Wait for Booted state.'
    until xcrun simctl list | grep -q -s "${name} (${deviceUDID}) (Booted)" ; do sim-printf '.' ; sleep 0.1 ; done ; sim-printf '\n'
    # still wait a few seconds for the things to start up…
    sim-printf '# ' ; sim-progress-wait 6 1
}


function sim-device-run-application(){
    # Usage: sim-device-run-application $deviceUDID $applicationID
    # Launch the application and waits until it exits.
    local deviceUDID="$1"
    local applicationID="$2"
    sim-printf '# Launch the application %s.\n'  "$applicationID"
    local dummy
    local pid
    local status
    local tries=6
    # a race condition / timing bug in SpringBoard, so if this doesn't work, we shall try again.
    while [[ $tries -ge 0 ]] ; do
        read dummy pid <<< $(xcrun simctl launch "$deviceUDID" "$applicationID")
        if [[ $pid -eq 0 ]] ; then
            sleep 0.5
            tries=$((tries-1))
            sim-printf '# Let us try again.\n'
        else
            break
        fi
    done
    if [[ $pid -eq 0 ]]; then
        sim-printf '# Aborted.\n'
    else
        sim-printf '# Wait for application %s to exit (pid=%d).\n' "$applicationID" "$pid"
        # note: we cannot use wait because:
        #        bash: wait: pid 35965 is not a child of this shell
        sim-printf '# ';sim-wait-process "$pid" 1
        sim-printf '# Completed\n'
    fi
}


function sim-device-path(){
    # Usage: sim-device-path $deviceUDID $applicationID
    # Print the path of the simulated device file system.
    local deviceUDID="$1"
    local applicationID="$2"
    local path=ERROR
    local tries=3
    while [[ $path = ERROR && $tries -gt 0 ]] ; do
        read path < <(xcrun simctl get_app_container  "$deviceUDID" "$applicationID" || echo ERROR)
        sleep 0.1
        tries=$((tries-1))
    done
    if [[ $tries -eq 0 ]] ; then
        sim-errorf 'sim-device-path: Cannot get the app container path.'
        return 1
    fi
    echo $path|sed -e "s:^\(/.*/${deviceUDID}\)/.*:\1:"
}

function sim-application-sandbox-path(){
    # Usage: sim-application-sandbox-path $deviceUDID $applicationID
    # Print the path of the application sandbox (where run-time file are stored).
    local deviceUDID="$1"
    local applicationID="$2"
    siminfo --application-sandboxPath "$deviceUDID" "$applicationID"
}

function sim-device-fetch-application-container(){
    # Usage: sim-device-fetch-application-container $deviceUDID $applicationID
    # Prints the path of the created tarball.
    local deviceUDID="$1"
    local applicationID="$2"
    local date=$(date +%Y%m%dT%H%M%S)
    local container="$(xcrun simctl get_app_container "$deviceUDID" "$applicationID")"
    local container_tarball="${CONTAINER_DIR}/${date}--${applicationID}--${deviceTypeID}--${simRuntimeID}--container.tar.bz2"

    sim-printf '# Fetch back the application container.\n'
    tar jcf "${container_tarball}" -C "$(dirname "${container}" )" "$(basename "${container}")"
    if [[ $SIM_TRACE -ne 0 ]] ; then
        sim-printf '%s=%s\n' container "${container_tarball}"
    fi
}


function sim-device-fetch-application-sandbox(){
    # Usage: sim-device-fetch-application-sandbox $deviceUDID $applicationID
    # Prints the path of the created tarball.
    local deviceUDID="$1"
    local applicationID="$2"
    local date=$(date +%Y%m%dT%H%M%S)
    local sandbox="$(sim-application-sandbox-path "$deviceUDID" "$applicationID")"
    local sandbox_tarball="${CONTAINER_DIR}/${date}--${applicationID}--${deviceTypeID}--${simRuntimeID}--sandbox.tar.bz2"

    if [[ -s "$sandbox" ]] ; then
        sim-printf '# Fetch back the application sandbox.\n'
        tar jcf "${sandbox_tarball}" -C "$(dirname "$sandbox" )" "$(basename "$sandbox" )"
        if [[ $SIM_TRACE -ne 0 ]] ; then
            sim-printf '%s=%s\n' sandbox "${sandbox_tarball}"
        fi
    else
        sim-printf '# No sandbox!\n'
    fi
}


function sim-run-application(){
    # Usage: sim-run-application $deviceTypeID $simRuntimeID $applicationPackage
    if [[ $# -lt 3 ]] ; then
        sim-errorf 'Missing arguments; usage: sim-run-application $deviceTypeID $simRuntimeID $applicationPackage'
        return 1
    fi
    local deviceTypeID="$1"
    local simRuntimeID="$2"
    local applicationPackage="$(absolutePath "$3")"
    local applicationID="$(ios-applicationID-from-package "$applicationPackage")"
    local name="${applicationID}--$$"
    sim-printf '# Create a new device.\n'
    local deviceUDID=$(sim-create-device "$name" "$deviceTypeID" "$simRuntimeID")
    if [[ -z "$deviceUDID" ]] ; then
        # error message already issued by sim-create-device.
        return $?
    fi
    if [[ $SIM_TRACE -ne 0 ]] ; then
        sim-printf "%s=%s\n" deviceUDID "$deviceUDID"
        sim-printf "%s=%s\n" applicationPackage "$applicationPackage"
        sim-printf "%s=%s\n" applicationID "$applicationID"
    fi
    sim-device-boot "$deviceUDID"
    local simpid=$top;pop
    sleep 2
    sim-device-install-application "$deviceUDID" "$applicationPackage"
    sleep 2
    sim-device-run-application "$deviceUDID" "$applicationID"
    sleep 2
    sim-device-fetch-application-container  "$deviceUDID" "$applicationID"
    sim-device-fetch-application-sandbox    "$deviceUDID" "$applicationID"
    sim-device-shutdown "$deviceUDID" "$simpid"
    sim-printf '# Delete the device %s.\n' "$deviceUDID"
    sim-delete-device "$deviceUDID"
}

function sim-quit-all-simulators(){
    # TODO: doesn't work correctly yet.
    while ps axlww|grep -q -s -F "${SIMULATOR_PACKAGE}" ; do
        osascript -e 'tell application "${SIMULATOR_NAME}" to quit'
        osascript -e 'tell application "iOS ${SIMULATOR_NAME}" to quit'
    done
}

function sim-delete-all-devices(){
    # TODO: doesn't work correctly yet.
    xcrun simctl erase all
}


iosSim_PROVIDED=true
#### THE END ####
