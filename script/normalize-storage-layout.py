#!/usr/bin/env python3
"""Normalize `forge inspect <C> storageLayout --json` into a stable, AST-id-free canonical form for
the storage-layout drift gate (audit F5).

Why this exists: the old gate diffed the human-readable `forge inspect` TABLE, which shows the proxy's
`ds` field as one opaque 2208-byte blob — so a reorder INSIDE ShwounsDAOTypes.Storage (or inside
Proposal / SnapshotState, which are reached through mapping VALUES) passed undetected. This normalizer
walks the COMPLETE reachable type graph and emits every struct's member layout, every mapping's
key/value, and every array's base + length, so any nested reorder shows up in the diff.

Normalization: solc embeds a per-compilation AST id in named-type ids (t_struct(Name)<id>_storage,
t_enum(Name)<id>, t_contract(Name)<id>, t_userDefinedValueType(Name)<id>). Those ids churn between
unrelated compilations without any layout change, so we strip ONLY them — canonicalizing named types
by their semantic NAME. We PRESERVE everything else verbatim: array lengths (t_array(...)46_storage
keeps 46 — critical so a __gap shrink from [50] to [46] is NOT masked), integer/bytes widths, and
mapping key/value type ids. After normalization we assert no two distinct original type ids collapse
to the same normalized id with DIFFERENT content (a collision would mean the normalization is too
aggressive and could hide a change) — failing loudly rather than masking.

Output: canonical JSON (sorted keys) with `storage` (top-level vars, absolute slot/offset — they are
statically embedded so absolute slots are meaningful) and `types` (every reachable type's RELATIVE
member layout + encoding + byteSize — absolute slots don't apply to mapping/array elements).
"""
import json
import re
import sys

# Matches the AST id that immediately follows a NAMED type's closing paren. Only these four kinds
# carry an identity id; t_array(...)<len> is deliberately NOT in this set (that trailing number is a
# fixed-array length we must keep).
_AST_ID = re.compile(r'(t_(?:struct|enum|contract|userDefinedValueType)\([^)]*\))\d+')


def norm_type(t):
    """Canonicalize a type-id string: drop the compiler AST id from named types, keep all else."""
    if t is None:
        return None
    return _AST_ID.sub(r'\1', t)


def norm_type_entry(entry):
    """Normalize one entry of the `types` map into a layout-only, AST-id-free record."""
    out = {
        "encoding": entry.get("encoding"),
        "numberOfBytes": entry.get("numberOfBytes"),
    }
    if "members" in entry:  # struct
        out["members"] = sorted(
            (
                {
                    "label": mm["label"],
                    "slot": str(mm["slot"]),
                    "offset": int(mm["offset"]),
                    "type": norm_type(mm["type"]),
                }
                for mm in entry["members"]
            ),
            key=lambda x: (int(x["slot"]), x["offset"], x["label"]),
        )
    if "key" in entry:  # mapping
        out["key"] = norm_type(entry["key"])
    if "value" in entry:  # mapping
        out["value"] = norm_type(entry["value"])
    if "base" in entry:  # array
        out["base"] = norm_type(entry["base"])
    return out


def main():
    raw = json.load(sys.stdin)
    storage = raw.get("storage", []) or []
    types = raw.get("types", {}) or {}

    norm_storage = sorted(
        (
            {
                "label": s["label"],
                "slot": str(s["slot"]),
                "offset": int(s["offset"]),
                "type": norm_type(s["type"]),
            }
            for s in storage
        ),
        key=lambda x: (int(x["slot"]), x["offset"], x["label"]),
    )

    norm_types = {}
    for orig_key, entry in types.items():
        nk = norm_type(orig_key)
        ne = norm_type_entry(entry)
        if nk in norm_types and norm_types[nk] != ne:
            sys.stderr.write(
                "normalize-storage-layout: COLLISION — distinct types normalize to '%s' with "
                "different layouts; normalization is unsafe for this artifact.\n" % nk
            )
            sys.exit(2)
        norm_types[nk] = ne

    out = {"storage": norm_storage, "types": dict(sorted(norm_types.items()))}
    json.dump(out, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
