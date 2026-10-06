#!/usr/bin/env bash

#"N: Skipping acquire of configured file 'main/binary-i386/Packages' as repository ...
#doesn't support architecture 'i386'" happens when i386 is enabled in dpkg but a repo's
#.sources stanza has no Architectures: line (apt modernize-sources drops the [arch=]
#bracket from the old .list format). For every such stanza, read the repo's own Release
#file and pin Architectures: to the dpkg architectures it actually supports.
#Also drops exact-duplicate stanzas within a file.
#Idempotent: stanzas that already have an Architectures: line are left alone, and repos
#whose Release can't be fetched (offline, authenticated) are skipped untouched.

SOURCES_DIR="${SOURCES_DIR:-/etc/apt/sources.list.d}"

dpkg_archs="$(dpkg --print-architecture) $(dpkg --print-foreign-architectures)"
[ "$(wc -w <<< "$dpkg_archs")" -lt 2 ] && exit 0   #no foreign arch enabled, nothing to warn about

#architectures a repo publishes, from its Release file ("" if it can't be fetched)
repo_archs() {
    local uri="${1%/}" suite="$2" url
    if [[ "$suite" == */ ]]; then url="$uri/${suite}InRelease"; else url="$uri/dists/$suite/InRelease"; fi
    curl -fsSL --max-time 20 "$url" 2>/dev/null | sed -n 's/^Architectures: *//p' | head -1
}

fix_stanza() {
    local stanza="$1" uri suite repo want a
    grep -q '^Architectures:' <<< "$stanza" && { printf '%s' "$stanza"; return; }
    uri="$(sed -n 's/^URIs: *//p' <<< "$stanza" | awk '{print $1}')"
    suite="$(sed -n 's/^Suites: *//p' <<< "$stanza" | awk '{print $1}')"
    [ -z "$uri" ] || [ -z "$suite" ] && { printf '%s' "$stanza"; return; }

    repo=" $(repo_archs "$uri" "$suite") "
    [ "$repo" = "  " ] && { printf '%s' "$stanza"; return; }   #couldn't read Release, leave as-is

    want=""
    for a in $dpkg_archs; do [[ "$repo" == *" $a "* ]] && want="$want $a"; done
    want="${want# }"
    #only pin when the repo is missing at least one dpkg arch (and supports at least one)
    if [ -n "$want" ] && [ "$(wc -w <<< "$want")" -lt "$(wc -w <<< "$dpkg_archs")" ]; then
        printf '%s\nArchitectures: %s\n' "${stanza%$'\n'}" "$want"
    else
        printf '%s' "$stanza"
    fi
}

for f in "$SOURCES_DIR"/*.sources; do
    [ -f "$f" ] || continue
    out="" stanza="" skip=0
    unset seen; declare -A seen
    #emit the (fixed) stanza, unless an identical one was already emitted - modernize-sources
    #appends rather than merges when a package recreates its .list next to an existing .sources,
    #leaving duplicate stanzas that make apt warn "Target ... is configured multiple times"
    flush() {
        [ -z "$stanza" ] && return
        local t; t="$(fix_stanza "$stanza")"
        if [ -n "${seen[$t]+x}" ]; then skip=1; else seen[$t]=1; out+="$t"$'\n'; fi
        stanza=""
    }
    while IFS= read -r line || [ -n "$line" ]; do
        if [ -z "$line" ]; then
            flush
            if [ "$skip" = 1 ]; then skip=0; else out+=$'\n'; fi
        else
            stanza+="$line"$'\n'
        fi
    done < "$f"
    flush
    printf '%s' "$out" > "$f.tmp"
    if cmp -s "$f" "$f.tmp"; then rm -f "$f.tmp"; else mv "$f.tmp" "$f"; echo "fixrepos: updated $f"; fi
done
