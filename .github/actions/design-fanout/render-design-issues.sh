#!/usr/bin/env bash
#
# Render a merged design folder into tracker-issue body files plus a manifest,
# with no API calls. The design-fanout action runs this before any issue is
# published, so body rendering and issue creation stay separate stages.
# Prints the design kind (flat | multi) on stdout.
#
# Usage: render-design-issues.sh <design-dir> <repo> <sha> <out-dir>
#
# Writes <out-dir>/manifest.tsv, one row per issue to create:
#   role<TAB>slug<TAB>title<TAB>type<TAB>marker<TAB>body-file
# role is epic | flat | unit. Body files live alongside the manifest.

set -euo pipefail

dir="$1"
repo="$2"
sha="$3"
out="$4"

mkdir -p "${out}"
manifest="${out}/manifest.tsv"
: > "${manifest}"

base=$(basename "${dir}")
id="${base%%-*}"
short="${base#*-}"

# ## Summary paragraph, stripped of leading/trailing blank lines.
summary() {
  awk '
    /^## Summary[[:space:]]*$/ {f=1; next}
    /^## / {f=0}
    f {
      if ($0 ~ /^[[:space:]]*$/) { if (seen) blanks++; next }
      for (; blanks>0; blanks--) print ""
      seen=1; print
    }
  ' "$1"
}

# Issue type from the file's `type:` frontmatter; empty if absent.
fm_type() { awk 'NR==1 && $0=="---"{i=1;next} i && $0=="---"{exit} i && /^type:/{sub(/^type:[[:space:]]*/,"");print;exit}' "$1"; }

# First `# ` H1 (the natural-language title); empty if the file has none.
title() { awk '/^# /{sub(/^#[[:space:]]+/,"");print;exit}' "$1"; }

# Body = summary paragraph, blank, Design: permalink, blank, marker.
render_body() {  # $1=source-file $2=marker $3=out-file
  {
    summary "$1"
    printf '\nDesign: https://github.com/%s/blob/%s/%s\n\n%s\n' "${repo}" "${sha}" "$1" "$2"
  } > "$3"
}

row() { printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" "$6" >> "${manifest}"; }

epic_marker="<!-- autocode:epic=${id} -->"

if [[ -d "${dir}/units" ]]; then
  etitle=$(title "${dir}/DESIGN.md"); etitle="${etitle:-${short}}"
  ebody="${out}/epic.md"
  render_body "${dir}/DESIGN.md" "${epic_marker}" "${ebody}"
  row epic "${short}" "${etitle}" epic "${epic_marker}" "${ebody}"

  for unit in "${dir}"/units/*.md; do
    [[ -f "${unit}" ]] || continue
    slug=$(basename "${unit}" .md)
    umarker="<!-- autocode:unit=${id}/${slug} -->"
    utitle=$(title "${unit}"); utitle="${utitle:-${slug}}"
    utype=$(fm_type "${unit}"); utype="${utype:-task}"
    ubody="${out}/unit-${slug}.md"
    render_body "${unit}" "${umarker}" "${ubody}"
    row unit "${slug}" "${utitle}" "${utype}" "${umarker}" "${ubody}"
  done
  echo multi
else
  ftitle=$(title "${dir}/DESIGN.md"); ftitle="${ftitle:-${short}}"
  ftype=$(fm_type "${dir}/DESIGN.md"); ftype="${ftype:-task}"
  fbody="${out}/epic.md"
  render_body "${dir}/DESIGN.md" "${epic_marker}" "${fbody}"
  row flat "${short}" "${ftitle}" "${ftype}" "${epic_marker}" "${fbody}"
  echo flat
fi
