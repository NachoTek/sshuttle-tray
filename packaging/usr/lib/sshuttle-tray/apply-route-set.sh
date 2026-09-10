#!/usr/bin/env bash
# sshuttle-tray Route Set apply validator — root-side oneshot helper.
#
# usage: apply-route-set.sh <staged-env-file> <dest-env-file>
#
# Reads the staged Route Set (KEY=value lines written by the Tool under
# /run/user/<uid>/sshuttle-tray/), validates SSHUTTLE_SUBNETS as
# space-separated IPv4 CIDRs (0/0 allowed, bare IPs mean /32) and the
# optional SSHUTTLE_PING_TARGET as a single hostname or IPv4 literal,
# warns when a literal-IP Ping Target lies outside the Route Set, then
# installs the normalized file atomically (temp + rename).
# Fails loudly on garbage; never touches the destination on rejection.

set -euo pipefail
set -f   # never pathname-expand staged tokens

if [ $# -ne 2 ]; then
    echo "usage: $0 <staged-file> <dest-file>" >&2
    exit 2
fi

src=$1
dst=$2

if [ ! -r "$src" ]; then
    echo "apply-route-set: cannot read staged file: $src" >&2
    exit 1
fi

subnets=""
ping_target=""
ping_set=false

while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
        ''|'#'*) continue ;;
        SSHUTTLE_SUBNETS=*)       subnets=${line#SSHUTTLE_SUBNETS=} ;;
        SSHUTTLE_PING_TARGET=*)   ping_target=${line#SSHUTTLE_PING_TARGET=}; ping_set=true ;;
    esac
done < "$src"

# trim and collapse whitespace
subnets=$(printf '%s' "$subnets" | tr -s '[:space:]' ' ')
subnets=${subnets#' '}; subnets=${subnets%' '}
ping_target=$(printf '%s' "$ping_target" | tr -d '[:space:]')

if [ -z "$subnets" ]; then
    echo "apply-route-set: SSHUTTLE_SUBNETS is missing or empty" >&2
    exit 1
fi

valid_cidr() {
    local t=$1 base pfx o
    [ "$t" = "0/0" ] && return 0
    base=${t%%/*}
    if [[ $t == */* ]]; then pfx=${t##*/}; else pfx=""; fi
    [[ $base =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] || return 1
    for o in "${BASH_REMATCH[@]:1:4}"; do
        [ "$o" -le 255 ] || return 1
    done
    if [ -n "$pfx" ]; then
        [[ $pfx =~ ^[0-9]{1,2}$ ]] || return 1
        [ "$pfx" -le 32 ] || return 1
    fi
    return 0
}

for tok in $subnets; do
    if ! valid_cidr "$tok"; then
        echo "apply-route-set: not a valid CIDR: $tok" >&2
        exit 1
    fi
done

if [ "$ping_set" = true ] && [ -n "$ping_target" ]; then
    if ! [[ $ping_target =~ ^[A-Za-z0-9._:-]+$ ]]; then
        echo "apply-route-set: SSHUTTLE_PING_TARGET is not a hostname or IPv4: $ping_target" >&2
        exit 1
    fi
fi

ip_to_int() {
    local IFS=.
    set -- $1
    echo $(( ($1 << 24) | ($2 << 16) | ($3 << 8) | $4 ))
}

is_ipv4() {
    [[ $1 =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] || return 1
    local o
    for o in "${BASH_REMATCH[@]:1:4}"; do
        [ "$o" -le 255 ] || return 1
    done
    return 0
}

cidr_contains() {
    local cidr=$1 ip=$2 base pfx mask
    [ "$cidr" = "0/0" ] && return 0
    base=${cidr%%/*}
    if [[ $cidr == */* ]]; then pfx=${cidr##*/}; else pfx=32; fi
    if [ "$pfx" -eq 0 ]; then return 0; fi
    mask=$(( (0xFFFFFFFF << (32 - pfx)) & 0xFFFFFFFF ))
    (( ($(ip_to_int "$base") & mask) == ($(ip_to_int "$ip") & mask) ))
}

if [ "$ping_set" = true ] && [ -n "$ping_target" ] && is_ipv4 "$ping_target"; then
    in_scope=false
    for tok in $subnets; do
        if cidr_contains "$tok" "$ping_target"; then in_scope=true; break; fi
    done
    if [ "$in_scope" = false ]; then
        echo "warning: Ping Target $ping_target is outside the Route Set — the Tool cannot verify through it"
    fi
fi

content="SSHUTTLE_SUBNETS=$subnets"$'\n'
if [ "$ping_set" = true ] && [ -n "$ping_target" ]; then
    content+="SSHUTTLE_PING_TARGET=$ping_target"$'\n'
fi

dst_dir=${dst%/*}
tmp=$(mktemp "$dst_dir/.route-set.env.XXXXXX")
trap 'rm -f "$tmp"' EXIT
printf '%s' "$content" > "$tmp"
chmod 644 "$tmp"
mv -f "$tmp" "$dst"
trap - EXIT
