# -*- mode:shell-script;coding:utf-8 -*-
####
#### bash functions to manage real iOS devices.
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

require os iosSim

function real-help(){
    # Usage: real-help
    sed -n -e 's/[#] Usage: //p' "${BASH_SOURCE[0]}"
}

function real-list-devices(){
    # Usage: real-list-devices --> { deviceUDID }
    system_profiler SPUSBDataType \
        | sed -n -E -e '/(iPhone|iPad)/,/Serial/s/ *Serial Number: *(.+)/\1/p'
}



# runtimeNameString=nil
# stateString=nil
# availabilityString=nil
# devicesString=nil
# nameString=nil
# udidString=nil

kindString=nil
sdkVersionString=nil
modelString=nil
modelVersionString=nil

function real-initStrings(){
    sim-initStrings
    if [[ ${nameString:-nil}  = nil ]] ; then
        for str in kind sdkVersion model modelVersion ; do
            make-string $str;eval ${str}String=\$top;pop
        done
    fi
}

function real-list-devices-with-version-0(){
    local model
    local version
    local udid
    local n=0
    local devices=nil
    instruments -s devices 2>/dev/null \
        |sed -n -E \
             -e 's/^(.*) \(([0-9.]+)\) \[([-0-9A-Fa-f]+)\]$/kind=real;udid="\3";sdk="\2";name="\1"/p' \
             -e 's/^(.*) \(([0-9.]+)\) \[([-0-9A-Fa-f]+)\] \(Simulator\)$/kind=sim;udid="\3";sdk="\2";name="\1"/p' \
        | while read record ; do
        eval "$record"
        make-string "$udidString"       ;make-string "$udid" ;cons
        make-string "$kindString"       ;make-string "$kind" ;cons
        make-string "$sdkVersionString" ;make-string "$sdk"  ;cons
        make-string "$nameString"       ;make-string "$name" ;cons
        poplist 4
        n=$((n+1))
    done
    poplist $n
    devices="$top";pop

    system_profiler SPUSBDataType \
        | awk -F: '
            BEGIN{
                inn=0;
            }
            /(iPad|iPhone)/{
                gsub(/ /,"",$1);
                printf "model=%s;",$1;
                inn=1;
            }
            /Version/{
                if(inn!=0){
                    gsub(/ /,"",$2);
                    printf "version=\"%s\";",$2;
                }
            }
            /Serial Number/{
                if(inn!=0){
                    gsub(/ /,"",$2);
                    printf "udid=\"%s\"\n",$2;
                    inn=0;
                 }
            }' \
        | while read record ; do
        eval "$record"
        push $devices;push $udidString;assoc
        if [[ $top = nil ]] ; then
            make-string "$udidString"         ;make-string "$udid"     ;cons
            make-string "$kindString"         ;make-string "real"      ;cons
            make-string "$modelString"        ;make-string "$model"    ;cons
            make-string "$modelVersionString" ;make-string "$version"  ;cons
            poplist 4
            push $devices;cons;devices=$top;pop
        else
            make-string "$modelString"        ;make-string "$model"    ;cons
            make-string "$modelVersionString" ;make-string "$version"  ;cons
            poplist 2
            nconc
        fi
    done
    push $devices;prin1;terpri
}

function real-list-devices-with-version(){
    local -a udids=()
    local -a kinds=()
    local -a models=()
    local -a modelVersions=()
    local -a sdkVersions=()
    local -a names=()
    local udid
    local kind
    local name
    local sdkVersion
    local model
    local modelVersion
    local i=0
    local n=0

    instruments -s devices 2>/dev/null \
        |sed -n -E \
             -e 's/^(.*) \(([0-9.]+)\) \[([-0-9A-Fa-f]+)\]$/kind=real;udid="\3";sdkVersion="\2";name="\1"/p' \
             -e 's/^(.*) \(([0-9.]+)\) \[([-0-9A-Fa-f]+)\] \(Simulator\)$/kind=sim;udid="\3";sdkVersion="\2";name="\1"/p' \
        | while read record ; do
        eval "$record"
        udids[$i]="$udid"
        kinds[$i]="$kind"
        sdkVersions[$i]="$sdkVersion"
        names[$i]="$name"
        models[$i]=""
        modelVersions[$i]=""
        i=$((i+1))
    done
    n=$i

    system_profiler SPUSBDataType \
        | awk -F: '
            BEGIN{
                inn=0;
            }
            /(iPad|iPhone)/{
                gsub(/ /,"",$1);
                printf "model=%s;",$1;
                inn=1;
            }
            /Version/{
                if(inn!=0){
                    gsub(/ /,"",$2);
                    printf "modelVersion=\"%s\";",$2;
                }
            }
            /Serial Number/{
                if(inn!=0){
                    gsub(/ /,"",$2);
                    printf "udid=\"%s\"\n",$2;
                    inn=0;
                 }
            }' \
        | while read record ; do
        eval "$record"
        i=$(index "$udid" udids)
        if [[ 0 -le $i ]] ; then
            models[$i]="$model"
            modelVersions[$i]="$modelVersion"
        fi
    done

    i=0
    while [[ $i -lt $n ]] ; do
    udids
    kinds
    models
    modelVersions
    sdkVersions
    names
        state availability
    local -a slots=(udid  runtimeName name)
    local -a format=()
    printf '%-36s %-8s %-11s %-11s %s'
    done
}


function real-list-applications(){
    # Usage: real-list-applications --> { deviceUDID applicationID }
    real-list-devices|while read deviceUDID ; do
        ios-deploy --list_bundle_id --id "$deviceUDID"|sort|while read applicationID ; do
            printf "%s %s\n" "$deviceUDID" "$applicationID"
        done
    done
}

function real-put-application-package(){
    local applicationPackage="$1"
    local applicationID=$(ios-applicationID-from-package "$applicationPackage")
    local dir="$(xdg_cache_directory)/iosReal"
    ensure_directory "$dir"
    ln -sf "$applicationPackage" "$dir/$applicationID"
}

function real-get-application-package(){
    local applicationID="$1"
    local dir="$(xdg_cache_directory)/iosReal"
    readlink "$dir/$applicationID"
}

function real-device-install-application(){
    # Usage: real-device-install-application $deviceUDID $applicationPackage
    local deviceUDID="$1"
    local applicationPackage="$2"
    local applicationID="$(ios-applicationID-from-package "$applicationPackage")"
    local status=0
    sim-printf '# Install the application %s.\n'  "$applicationPackage"
    ios-deploy --id "$deviceUDID" --bundle "$applicationPackage" --nostart ; status=$?
    if [[ $status -eq 0 ]]; then
        real-put-application-package "$applicationPackage"
        sim-printf '# Installed %s\n' "$applicationID"
        return 0
    fi
    sim-errorf 'Could not install the application.'
    return $status
}

function real-device-run-application(){
    # Usage: real-device-run-application $deviceUDID $applicationID
    # Launch the application and waits until it exits.
    local deviceUDID="$1"
    local applicationID="$2"
    local debug="${3-no}"
    local debug_options=(--noninteractive)
    local applicationPackage="$(real-get-application-package "$applicationID")"
    if [[ "${debug}" != no ]] ; then
        debug_options=(--debug)
    fi
    sim-printf '# Launch the application %s.\n'  "$applicationID"
    ios-deploy --id "$deviceUDID" --bundle "$applicationPackage" --noinstall  "${debug_options[@]}"
}

function real-device-fetch-application-container(){
    # Usage: real-device-fetch-application-container $deviceUDID $applicationID
    # Prints the path of the application sandbox tarball (where the executable and resources are stored).
    local deviceUDID="$1"
    local applicationID="$2"
    local date=$(date +%Y%m%dT%H%M%S)
    local deviceTypeID="DEVICETYPE"
    local simRuntimeID="SDK"
    # local container="$(ios-applicationID-from-package "$applicationPackage")"
    local container_tarball="${CONTAINER_DIR}/${date}--${applicationID}--${deviceTypeID}--${simRuntimeID}--container.tar.bz2"
    sim-errorf "${FUNCNAME} is not implemented yet."
    # sim-printf '# Fetch back the application sandbox.\n'
    # tar jcf "${container_tarball}" -C "$(dirname "${container}")" "$(basename "${container}")"
    # if [[ $SIM_TRACE -ne 0 ]] ; then
    #     sim-printf '%s=%s\n' container "${container_tarball}"
    # fi
    # echo "$container_tarball"
}

function real-device-fetch-application-sandbox(){
    # Usage: real-device-fetch-application-sandbox $deviceUDID $applicationID
    # Prints the path of the application sandbox tarball (where the executable and resources are stored).
    local deviceUDID="$1"
    local applicationID="$2"
    local date=$(date +%Y%m%dT%H%M%S)
    local sandbox=${date}--${applicationID}--${deviceTypeID}--${simRuntimeID}--sandbox
    local sandbox_tarball="${CONTAINER_DIR}/${date}--${applicationID}--${deviceTypeID}--${simRuntimeID}--sandbox.tar.bz2"

    mkdir -p "/tmp/$$/$sandbox"
    (
        cd "/tmp/$$/$sandbox"
        sim-printf '# Fetch back the application sandbox.\n'
        ios-deploy --id "$deviceUDID" --bundle_id "$applicationID" --download # downlaods app tree
    )
    tar jcf "${sandbox_tarball}" -C "/tmp/$$" "$sandbox"
    if [[ $SIM_TRACE -ne 0 ]] ; then
        sim-printf '%s=%s\n' sandbox "${sandbox_tarball}"
    fi
    rm -rf "/tmp/$$/$sandbox"
    rmdir "/tmp/$$" 2>/dev/null || true
    echo "$sandbox_tarball"
}


function real-run-application(){
    # Usage: real-run-application $deviceUDID $applicationPackage
    local deviceUDID="$1"
    local applicationPackage="$(absolutePath "$2")"
    local debug="${3-no}"
    local applicationID="$(ios-applicationID-from-package "$applicationPackage")"
    local name="${applicationID}--$$"
    if [[ $SIM_TRACE -ne 0 ]] ; then
        sim-printf "%s=%s\n" deviceUDID "$deviceUDID"
        sim-printf "%s=%s\n" applicationPackage "$applicationPackage"
        sim-printf "%s=%s\n" applicationID "$applicationID"
    fi
    real-device-install-application "$deviceUDID" "$applicationPackage"
    sleep 2
    real-device-run-application "$deviceUDID" "$applicationID" "${debug}"
    sleep 2
    real-device-fetch-application-container  "$deviceUDID" "$applicationID"
    real-device-fetch-application-sandbox    "$deviceUDID" "$applicationID"
}


# instruments -s devices 2>/dev/null
# Known Devices:
# macbook-trustonic [BCF01102-73B6-57F4-BF60-D280D752E565]
# neso (9.3) [f69f4e9dd8728ae3c4bec7d27bd484d7096fa96a]
# Apple TV 1080p (9.2) [76DD1048-8A06-4603-AAA4-4216142C31F1] (Simulator)
# iPad 2 (8.1) [70FCDF38-2AE4-46BC-9C5F-F1A3DDB0F380] (Simulator)
# iPad 2 (8.2) [9458BF21-0B07-4724-A569-543C07A6C707] (Simulator)
# iPad 2 (8.3) [7681145B-DBA5-4073-8EC6-064094685AE2] (Simulator)
# iPad 2 (8.4) [183101EE-3AD3-4D73-BEC3-AD01FE3F927B] (Simulator)
# iPad 2 (9.0) [E349E4B3-2CDC-4888-A1C2-C0DBF8CAA49B] (Simulator)
# iPad 2 (9.1) [D2E652C6-F29B-4D58-AD15-3EB20F517389] (Simulator)


iosReal_PROVIDED=true
#### THE END ####
