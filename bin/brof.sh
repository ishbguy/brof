#!/usr/bin/env bash
# Copyright (c) 2021 Herbert Shen <ishbguy@hotmail.com> All Rights Reserved.
# Released under the terms of the MIT License.
#
# A simple bash shell script profiler.
#

# source guard
[[ $BROF_SOURCED -eq 1 ]] && return
readonly BROF_SOURCED=1
readonly BROF_ABS_SRC="$(readlink -f "${BASH_SOURCE[0]}")"
readonly BROF_ABS_DIR="$(dirname "$BROF_ABS_SRC")"

# utils
BROF_EXIT_CODE=0
warn() { echo -e "$@" >&2; ((++BROF_EXIT_CODE)); return ${WERROR:-1}; }
die() { echo -e "$@" >&2; exit $((++BROF_EXIT_CODE)); }
debug() { [[ $DEBUG == 1 ]] && echo "$@" || true; }
usage() { echo -e "$HELP"; }
version() { echo -e "$PROGNAME $VERSION"; }
defined() { declare -p "$1" &>/dev/null; }
definedf() { declare -f "$1" &>/dev/null; }
is_sourced() { [[ -n ${FUNCNAME[1]} && ${FUNCNAME[1]} != "main" ]]; }
is_array() { local -a def=($(declare -p "$1" 2>/dev/null)); [[ ${def[1]} =~ a ]]; }
is_map() { local -a def=($(declare -p "$1" 2>/dev/null)); [[ ${def[1]} =~ A ]]; }
has_tool() { hash "$1" &>/dev/null; }
ensure() {
    local cmd="$1"; shift
    local -a info=($(caller 0))
    (eval "$cmd" &>/dev/null) || \
        die "${info[2]}:${info[0]}:${info[1]}:${FUNCNAME[0]} '$cmd' failed. " "$@"
}
pargs() {
    ensure "[[ $# -ge 3 ]]" "Need OPTIONS, ARGUMENTS and OPTSTRING"
    ensure "[[ -n $1 && -n $2 && -n $3 ]]" "Args should not be empty."
    ensure "is_map $1 && is_map $2" "OPTIONS and ARGUMENTS should be map."

    local -n __opt="$1"
    local -n __arg="$2"
    local optstr="$3"
    shift 3

    OPTIND=1
    while getopts "$optstr" opt; do
        [[ $opt == ":" || $opt == "?" ]] && die "$HELP"
        __opt[$opt]=1
        __arg[$opt]="$OPTARG"
    done
    shift $((OPTIND - 1))
}
require() {
    ensure "[[ $# -gt 2 ]]" "Not enough args."
    ensure "definedf $1" "$1 should be a defined func."

    local -a miss
    local cmd="$1"
    local msg="$2"
    shift 2
    for obj in "$@"; do
        "$cmd" "$obj" || miss+=("$obj")
    done
    [[ ${#miss[@]} -eq 0 ]] || die "$msg: ${miss[*]}."
}
require_var() { require defined "You need to define vars" "$@"; }
require_func() { require definedf "You need to define funcs" "$@"; }
require_tool() { require has_tool "You need to install tools" "$@"; }

profile() {
    awk '
BEGIN {
    PROCINFO["sorted_in"]="@val_num_asc"
}
/^\+/ {
    # refresh vars with new record
    time = $2
    prev = $3
    curr = $4

    # first init last vars
    if (NR == 1) {
        last_time = time
        last_prev = prev
        last_curr = curr
    }

    # count function call and sum time comsumed
    if (prev == last_curr) {
        count[prev]++
        call_stack[prev]=1
    } else if (prev != last_prev) {
        delete call_stack[last_prev]
    }
    for (f in call_stack) {
        cost[f] += 0 + time - last_time
    }
    sum += time - last_time

    # refresh last record
    last_time = time
    last_prev = prev
    last_curr = curr
}
END {
    printf("%-20s\tCount\tTotal-Cost\tAverage-Cost\tPercent\n", "Function")
    for (f in cost) {
        printf("%-20s\t%-5d\t%f\t%f\t%f\n", f, count[f], cost[f], cost[f]/(count[f]>0?count[f]:1), cost[f]/sum)
    }
}'
}

brof() {
    local PROGNAME="$(basename "${BASH_SOURCE[0]}")"
    local VERSION="v0.1.0"
    local HELP=$(cat <<EOF
$PROGNAME $VERSION
$PROGNAME [-hvD] args
    
    -h  print this help message 
    -v  print version number
    -D  turn on debug mode

This program is released under the terms of the MIT License.
EOF
)

    require_tool awk

    local -A opts=() args=()
    pargs opts args 'hvD' "$@"
    shift $((OPTIND - 1))
    [[ ${opts[h]} ]] && usage && return 0
    [[ ${opts[v]} ]] && version && return 0
    [[ ${opts[D]} ]] && set -x

    ensure "[[ $# -ge 1 ]]" "Need a bash shell script filename!"
    ensure "[[ -e $1 ]]" "$1 does not exist!"

    # execute in subshell
    (
        PS4='+ $(date +%s.%N) $([ -z ${FUNCNAME[1]} ] && echo "NULL main" || echo "${FUNCNAME[1]} ${FUNCNAME[0]}") : '
        bash -x "$@" 2>&1
    ) | profile
}

is_sourced || brof "$@"

# vim:set ft=sh ts=4 sw=4:
