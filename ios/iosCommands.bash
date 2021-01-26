# -*- mode:shell-script;coding:utf-8 -*-
####
#### bash wrapper functions to call ios commands.
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

require os

function simctl(){
    xcrun simctl "$@"
}

function ios-help-compile-qa-tools(){
    sim-errorf 'Please compile ios-deploy and siminfo with something like:'
    sim-errorf '    cd %s' "${COMP_PATH_Scripts:?}/../../../qa/Tools/ios-deploy"
    sim-errorf '    mvn compile -D PLATFORM=IOS -D TOOLCHAIN=XCODE -D MODE=Release'
    sim-errorf '    cd %s' "${COMP_PATH_Scripts:?}/../../../qa/Tools/siminfo"
    sim-errorf '    mvn compile -D PLATFORM=IOS -D TOOLCHAIN=XCODE -D MODE=Release'
}

function ios-deploy(){
    if [[ -z "${COMP_PATH_IosDeploy-}" ]] ; then
        COMP_PATH_IosDeploy="${COMP_PATH_Scripts:?}/../../../qa/Tools/ios-deploy"
    fi
    if [[ -x "${COMP_PATH_IosDeploy}/Out/IOS/bin/ios-deploy" ]] ; then
        "${COMP_PATH_IosDeploy}/Out/IOS/bin/ios-deploy" "$@"
    else
        sim-errorf 'ios-deploy does not seem to be installed.'
        ios-help-compile-qa-tools
        exitIfScript
    fi
}

function siminfo(){
    if [[ -z "${COMP_PATH_SimInfo-}" ]] ; then
        COMP_PATH_SimInfo="${COMP_PATH_Scripts:?}/../../../qa/Tools/siminfo"
    fi
    if [[ -x "${COMP_PATH_SimInfo}/Out/IOS/bin/siminfo" ]] ; then
        "${COMP_PATH_SimInfo}/Out/IOS/bin/siminfo" "$@"
    else
        sim-errorf 'siminfo does not seem to be installed.'
        ios-help-compile-qa-tools
        exitIfScript
    fi
}

provide iosCommands
