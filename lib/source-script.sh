#!/usr/bin/env bash
# What every Script does the same way, in one place (#75).
#
# A Script is one Source's own program, but most of what it does is not about
# its Source: the Requirement preflight and the Blocked report are plugin-wide
# rules (ADR 0005), first registration of an Account wins for every Source, and
# the settings page parses one listing shape whichever Script answered it. Those
# parts live here, so a Script is only its Source's endpoint, detection paths
# and key names.
#
# Sourcing this file only defines: nothing here reads a credential, makes a
# request or exits, until the Script calls require_requirements.
#
# A Script sources it as:
#
#     SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
#     if ! . "$SCRIPT_DIR/lib/source-script.sh" 2>/dev/null; then
#         printf 'CREDS_STATUS=blocked\n'
#         printf 'BLOCKING_REQUIREMENT=%s\n' 'lib/source-script.sh'
#         exit 0
#     fi
#
# SCRIPT_DIR is the caller's: this file is sourced, so $0 is still the Script.
#
# The Account origins a Script reports are display text: the path, directory or
# environment variable a credential was found at, in the form the plugin's own
# descriptions already use. A tilde in one is meant literally, not as a shell
# expansion to perform.
# shellcheck disable=SC2088

# The keys the Account list is reported under. Claude's Accounts are Profiles on
# the wire, so it sets both before sourcing; every other Source takes these.
ACCOUNT_LIST_KEY="${ACCOUNT_LIST_KEY:-ACCOUNTS}"
ACCOUNT_KEY_PREFIX="${ACCOUNT_KEY_PREFIX:-ACCOUNT_}"

# The registry: one entry per Account, parallel by index. The value is whatever
# identifies the Account to its Source, an API key or a resolved directory, and
# the Script that registered it is what knows which.
ACCOUNT_NAMES=()
ACCOUNT_VALUES=()
ACCOUNT_ORIGINS=()
ACCOUNT_SHADOWED=()

# Whether this run is the settings page asking for the Account list rather than
# the widget asking for usage. Set by parse_account_args, read by the Script.
LIST_ACCOUNTS=0

# A Requirement is a command-line program a Script cannot read any data without.
# plugin.json declares them, and the check runs before anything else: with a
# Requirement absent nothing downstream can be read, so a swallowed jq failure
# would report a credential verdict instead of naming the real cause (ADR 0005).
#
# The names are read from the manifest with sed and tr rather than jq, because
# the program doing the checking is the one that may be missing.
requirement_names() {
    sed -n '/"requires"[[:space:]]*:[[:space:]]*\[/,/\]/p' "$1" \
        | tr -d '[:space:]"' \
        | sed -e '1s/^[^:]*://' -e 's/[][]//g' \
        | tr ',' '\n' \
        | sed '/^$/d'
}

# The Requirements this machine does not have, comma-separated. Presence only: a
# jq that exists and fails is the call's own business and reports Blocked from
# where it fails.
missing_requirements() {
    local name out=""
    while IFS= read -r name; do
        [ -n "$name" ] || continue
        command -v "$name" >/dev/null 2>&1 || out="${out:+$out,}$name"
    done < <(requirement_names "$SCRIPT_DIR/plugin.json")
    printf '%s' "$out"
}

# The report a Script emits when it cannot read a credential: the state, the
# commands that blocked it, and an empty Account list so a listing parses. The
# origins and shadowed keys answer only the listing, which asks for them.
#
# blocked_report <commands> [the Script's own arguments]
blocked_report() {
    local commands="$1"
    shift
    printf 'CREDS_STATUS=blocked\n'
    printf 'BLOCKING_REQUIREMENT=%s\n' "$commands"
    printf '%s=\n' "$ACCOUNT_LIST_KEY"
    for arg in "$@"; do
        if [ "$arg" = "--list-accounts" ]; then
            printf '%sORIGINS=\n' "$ACCOUNT_KEY_PREFIX"
            printf '%sSHADOWED=\n' "$ACCOUNT_KEY_PREFIX"
            break
        fi
    done
}

# The preflight itself, called before a Script reads anything. With a Requirement
# missing it reports Blocked and ends the Script: no credential is read and no
# request is made.
#
# require_requirements [the Script's own arguments]
require_requirements() {
    local missing
    missing=$(missing_requirements)
    [ -n "$missing" ] || return 0
    blocked_report "$missing" "$@"
    exit 0
}

# add_account <name> <value> <origin>
# First registration of a name (or of a value) wins, so the order a Script's
# callers run in is its precedence order. The value is what identifies the
# Account to its Source: an API key, or a directory the Script has already
# resolved, because the comparison here is a string one. The origin is where it
# was found, as the user would look for it: a file's path, the name of an
# environment variable, or "custom" for an entry from the plugin's Custom
# Account list.
add_account() {
    local name="$1" value="$2" origin="${3:-}"

    # , | : are output delimiters, they cannot survive in an account name. An
    # origin is display text: the list it rides is comma-separated and the other
    # Account lists separate entries with |, so neither can survive in it either.
    # The ":" that separates an origin from its name is left alone, because a
    # pair is split on its first colon and a path may carry one.
    name="${name//[,|:]/}"
    origin="${origin//[,|]/}"
    [ -n "$name" ] || return 0
    [ -n "$value" ] || return 0

    local idx
    # Nothing to clash with while the list is empty, and the guard keeps that
    # true on a bash that cannot expand an empty indexed list under set -u.
    if [ "${#ACCOUNT_NAMES[@]}" -gt 0 ]; then
        for idx in "${!ACCOUNT_NAMES[@]}"; do
            if [ "${ACCOUNT_NAMES[$idx]}" = "$name" ] || [ "${ACCOUNT_VALUES[$idx]}" = "$value" ]; then
                # Only a clash a user can act on is reported: one side of it has
                # to be a Custom Account. Two detected registrations clashing is
                # the Script's own precedence, which its description explains.
                if [ "$origin" = "custom" ] || [ "${ACCOUNT_ORIGINS[$idx]}" = "custom" ]; then
                    ACCOUNT_SHADOWED+=("${ACCOUNT_NAMES[$idx]}|${name}:${origin}")
                fi
                return 0
            fi
        done
    fi

    ACCOUNT_NAMES+=("$name")
    ACCOUNT_VALUES+=("$value")
    ACCOUNT_ORIGINS+=("$origin")
}

# account_origins -> "name:origin,name:origin". The form the per-Account lists
# already use, so the settings page parses one shape.
account_origins() {
    local out="" idx
    # An empty list has nothing to join, and the guard keeps the expansion valid
    # on a bash that cannot expand an empty indexed list under set -u.
    if [ "${#ACCOUNT_NAMES[@]}" -gt 0 ]; then
        for idx in "${!ACCOUNT_NAMES[@]}"; do
            out="${out:+${out},}${ACCOUNT_NAMES[$idx]}:${ACCOUNT_ORIGINS[$idx]}"
        done
    fi
    printf '%s' "$out"
}

# account_shadowed -> "<winner>|<name>:<origin>" for the registrations the list
# refused because something already held their name or their value: what kept it,
# then what lost and where it came from. The settings page is how the user learns
# that a Custom Account took a detected one's place, which is otherwise only
# visible as an API rejection. The winner makes that link explicit even when the
# two names differ, as they do when the value is what clashed.
account_shadowed() {
    local out="" idx
    # An empty list has nothing to join, and the guard keeps the expansion valid
    # on a bash that cannot expand an empty indexed list under set -u.
    if [ "${#ACCOUNT_SHADOWED[@]}" -gt 0 ]; then
        for idx in "${!ACCOUNT_SHADOWED[@]}"; do
            out="${out:+${out},}${ACCOUNT_SHADOWED[$idx]}"
        done
    fi
    printf '%s' "$out"
}

# The arguments both callers pass: the settings page's Account editor asks for
# the list with the same name=value arguments the widget fetches with, so the two
# agree about which Account a name refers to. A value may carry an equals sign,
# so the split is on the first one only.
#
# parse_account_args [the Script's own arguments]
parse_account_args() {
    local arg
    # LIST_ACCOUNTS is read by the Script that sourced this file, not here.
    # shellcheck disable=SC2034
    for arg in "$@"; do
        case "$arg" in
            "--list-accounts") LIST_ACCOUNTS=1 ;;
            *=*) add_account "${arg%%=*}" "${arg#*=}" "custom" ;;
        esac
    done
}

# The listing answer. It says why it is empty when it is: an empty Account list
# is a Script's own Not installed state, and the settings page needs to know that
# as a state of the Source rather than as a verdict on the user's rows.
emit_account_listing() {
    printf '%s=%s\n' "$ACCOUNT_LIST_KEY" "$(IFS=,; echo "${ACCOUNT_NAMES[*]:-}")"
    printf '%sORIGINS=%s\n' "$ACCOUNT_KEY_PREFIX" "$(account_origins)"
    printf '%sSHADOWED=%s\n' "$ACCOUNT_KEY_PREFIX" "$(account_shadowed)"
    if [ "${#ACCOUNT_NAMES[@]}" -eq 0 ]; then
        printf 'CREDS_STATUS=not_installed\n'
    fi
}

# The value of one line in a result file, or the given default when the line is
# absent or empty. The default is applied outside the pipeline that reads the
# value, because `grep | cut || echo` binds `||` to cut, whose exit status is 0
# even when grep matched nothing (#59).
result_value() {
    local file="$1" key="$2" default="$3" value
    value=$(grep "^${key}=" "$file" 2>/dev/null | cut -d= -f2-)
    printf '%s' "${value:-$default}"
}

# --- The shared pricing cache (ADR 0006) ---
#
# Cost figures are notional: what a Source's tokens would have cost at the
# provider's published API rates, not what the subscription was paid. The rates
# come from LiteLLM's price table, fetched at most once a day into one cache
# the plugin owns. One cache, not one per Source: Z.ai has no config directory
# to keep a file in, and the two Scripts that price would otherwise fetch the
# same table twice a day. Claude's Script predates this and is upstream's file,
# so it keeps its own cache.
#
# A Script calls load_pricing on its fetch path only. Both Scripts answer the
# settings page's --list-accounts request before reaching it, so opening the
# settings page spends no request on prices; a Source that reports Not
# installed ends before reaching it too.
#
# The cache carries OpenAI's and Z.ai's own rates - the two families the
# pricing Scripts read. Entries under another provider (a reseller, a gateway)
# price the same model differently and are left out, so a figure never mixes
# two rate sources. A rate the table omits falls back to the input rate for
# cache reads and to free for cache writes, which is what the providers' own
# terms make them: OpenAI charges nothing to write its cache.
LITELLM_URL="https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"
PRICING_JSON=""
PRICING_AWK=""
USD_EUR_RATE="0"

# The cache's path, resolved when it is needed rather than when the library is
# sourced: a caller that adjusts XDG_CACHE_HOME after sourcing - a test
# isolating itself - still gets the right directory.
pricing_cache_file() {
    printf '%s' "${XDG_CACHE_HOME:-${HOME}/.cache}/dms-ai-usage/pricing.json"
}

# Fetch the table and the USD→EUR rate, and write the cache. Returns non-zero
# when nothing worth caching was read; the caller decides what that leaves.
refresh_pricing() {
    local raw result eur_rate check tmp cache
    cache=$(pricing_cache_file)
    raw=$(curl -s --max-time 10 "$LITELLM_URL" 2>/dev/null) || return 1
    result=$(printf '%s' "$raw" | jq -c --arg d "$(date +%Y-%m-%d)" '
        {
            updated: $d,
            models: (with_entries(
                select(.value.litellm_provider == "openai" or .value.litellm_provider == "zai")
                | select((.value.input_cost_per_token // 0) > 0)
                | select(.value.litellm_provider == "zai" or (.key | test("^(gpt-|codex-|chatgpt-|o[134](-|$))")))
                | .value = {
                    input: .value.input_cost_per_token,
                    output: .value.output_cost_per_token,
                    cache_read: (.value.cache_read_input_token_cost // .value.input_cost_per_token),
                    cache_write: (.value.cache_creation_input_token_cost // 0)
                  }
            ))
        }' 2>/dev/null) || return 1
    eur_rate=$(curl -s --max-time 5 "https://api.frankfurter.dev/v1/latest?base=USD&symbols=EUR" 2>/dev/null \
        | jq -r '.rates.EUR // empty' 2>/dev/null) || eur_rate=""
    if [ -n "$eur_rate" ] && [[ "$eur_rate" =~ ^[0-9]+\.?[0-9]*$ ]]; then
        result=$(printf '%s' "$result" | jq -c --argjson r "$eur_rate" '. + {usd_eur_rate: $r}' 2>/dev/null) || return 1
    fi
    check=$(printf '%s' "$result" | jq -r '.models | length' 2>/dev/null) || return 1
    [ "${check:-0}" -gt 0 ] 2>/dev/null || return 1
    # The Scripts run in parallel, so two refreshes can race. Each writes its
    # own temporary and renames it into place, so a reader sees the whole
    # previous cache or the whole new one, never a half-written file.
    mkdir -p "${cache%/*}" 2>/dev/null || return 1
    tmp=$(mktemp "${cache%/*}/.pricing.XXXXXX") || return 1
    if printf '%s\n' "$result" > "$tmp" 2>/dev/null && mv -f "$tmp" "$cache" 2>/dev/null; then
        return 0
    fi
    rm -f "$tmp"
    return 1
}

# Load the cache, refreshing it when it is stale or absent, and flatten the
# model rates into the awk string the counting passes read:
# "model:input:output:cache_read:cache_write,...". A refresh that fails keeps
# yesterday's cache, so a network blip prices from slightly old rates rather
# than dropping the cost figures until it heals.
load_pricing() {
    PRICING_JSON=""
    PRICING_AWK=""
    USD_EUR_RATE="0"
    local today cached_date cache
    cache=$(pricing_cache_file)
    today=$(date +%Y-%m-%d)
    if [ -f "$cache" ]; then
        cached_date=$(jq -r '.updated // ""' "$cache" 2>/dev/null || echo "")
        [ "$cached_date" = "$today" ] || refresh_pricing || true
    else
        refresh_pricing || true
    fi
    [ -f "$cache" ] || return 0
    PRICING_JSON=$(cat "$cache" 2>/dev/null) || PRICING_JSON=""
    [ -n "$PRICING_JSON" ] || return 0
    # The flattened rates and the currency rate are read by the Script that
    # sourced this library, not here.
    # shellcheck disable=SC2034
    PRICING_AWK=$(printf '%s' "$PRICING_JSON" | jq -r '
        [.models | to_entries[] | "\(.key):\(.value.input):\(.value.output):\(.value.cache_read):\(.value.cache_write)"]
        | join(",")' 2>/dev/null || echo "")
    # shellcheck disable=SC2034
    USD_EUR_RATE=$(printf '%s' "$PRICING_JSON" | jq -r '.usd_eur_rate // 0' 2>/dev/null || echo "0")
}

# Write a result file all-or-nothing: a reader sees the whole file or none of it,
# never a half-written one. The temporary sits beside the destination, so the
# rename that publishes it is atomic.
write_usage_result() {
    local out_file="$1"
    shift
    local tmp="${out_file}.tmp.$$"
    if printf '%s\n' "$@" 2>/dev/null > "$tmp"; then
        mv -f "$tmp" "$out_file" 2>/dev/null || rm -f "$tmp"
    else
        rm -f "$tmp"
    fi
}
