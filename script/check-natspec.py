#!/usr/bin/env python3
"""NatSpec coverage gate for the Shwouns protocol.

Makes "every function is documented" a reproducible build check rather than a judgment call,
so it can gate CI alongside ./script/check-storage-layout.sh.

WHY THE AST (not the ABI)
-------------------------
A flat ABI flattens inherited functions and synthesizes a getter for every public state variable,
so diffing NatSpec against the ABI would demand documentation on members a contract does not itself
declare (inherited OpenZeppelin / forked-Nouns / ERC-6551 APIs, and synthesized getters). Instead we
read the compiler AST that `forge build` emits into each artifact (foundry.toml: `ast = true`,
artifact key `"ast"`). The AST attributes every member to its DECLARATION SITE: we walk only the
member nodes physically declared inside an in-scope contract, which automatically excludes everything
inherited from out-of-scope bases and the synthesized public getters.

SCOPE (Groups A + B — see CLAUDE.md "File authority" and docs/DOCUMENTATION_PLAN.md)
-----------------------------------------------------------------------------------
  Group A  original work          — full NatSpec on every declared external/public function, event,
                                     error, and public state variable; internal/private functions are
                                     reported as ADVISORY (see below).
  Group B  forked Nouns, glasses  — same external/public/event/error/public-var requirement on members
           removed                  this fork declares.
Group C/D (forked libs / ERC-6551 reference / Tokenbound abstracts / *.original) are OUT OF SCOPE:
they are documented in curated pages (docs/architecture/), never by editing the files, so the gate
does not process them.

HARD GATE (exit 1 on any gap)
-----------------------------
For each member DECLARED in an in-scope contract/interface/library:
  - external/public function (kind == "function")  → requires @notice, a @param for every NAMED
                                                      parameter, and >= one @return per return value.
  - event                                           → requires @notice.
  - custom error                                    → requires @notice.
  - public state variable (incl. constant/immutable)→ requires @notice (checked on the variable's own
                                                      NatSpec, NOT the synthesized getter).
A member whose documentation contains `@inheritdoc` counts as fully documented (its tags come from the
named base/interface) and is not checked further. Constructors, receive(), fallback(), and modifiers
are exempt from the hard gate.

ADVISORY (never fails the build unless --strict-internal)
---------------------------------------------------------
The plan asks for at least @dev on Group-A *security-critical* internal/private functions, but
"security-critical" vs "trivial helper" cannot be classified mechanically, so undocumented Group-A
internal/private functions are listed as ADVISORY for the human pass instead of hard-failing (which
would force noise comments onto trivial helpers). The escrow / auth / finalize / refund / collect
paths are reviewed by hand. Pass --strict-internal to promote these to hard failures in CI.

USAGE
-----
  forge build            # emits the AST (ast = true); run first, or artifacts will be stale/absent
  python3 script/check-natspec.py            # report + exit code
  python3 script/check-natspec.py --quiet    # only the summary + failures
  python3 script/check-natspec.py --strict-internal   # also fail on undocumented Group-A internals
"""

import json
import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
OUT = REPO / "out"

# --- Scope: project-relative paths matching the AST's `absolutePath` ---------------------------------
# Group A — original work (full NatSpec + advisory internal @dev).
GROUP_A = [
    "src/auction/ShwounsAuctionHouse.sol",
    "src/governance/ShwounsDAOLogic.sol",
    "src/governance/ShwounsDAOProposals.sol",
    "src/governance/ShwounsDAOSignatures.sol",
    "src/governance/ShwounsDAOQuorum.sol",
    "src/governance/ShwounsDAOInterfaces.sol",
    "src/governance/GovernanceAuthRegistry.sol",
    "src/governance/GovernedOwnable.sol",
    "src/governance/ProposalEscrow.sol",
    "src/governance/Bootstrap.sol",
    "src/governance/data/ShwounsDAOData.sol",
    "src/rewards/GovernanceRewards.sol",
    "src/rewards/GovernanceIncentivesNFT.sol",
    "src/rewards/ApprovalRegistry.sol",
    "src/vault/ShwounsVault.sol",
    "src/vault/ShwounsVaultRegistry.sol",
    "src/vault/IShwounsVaultRegistry.sol",
]
# Group B — forked Nouns, glasses removed (full NatSpec on members this fork declares).
GROUP_B = [
    "src/token/ShwounsToken.sol",
    "src/token/ShwounsDescriptor.sol",
    "src/token/ShwounsSeeder.sol",
    "src/token/ShwounsArt.sol",
    "src/interfaces/IShwounsToken.sol",
    "src/interfaces/IShwounsAuctionHouse.sol",
    "src/interfaces/IShwounsDescriptor.sol",
    "src/interfaces/IShwounsDescriptorMinimal.sol",
    "src/interfaces/IShwounsSeeder.sol",
    "src/interfaces/IShwounsArt.sol",
]
IN_SCOPE = {p: ("A" if p in GROUP_A else "B") for p in GROUP_A + GROUP_B}


def doc_text(node):
    """NatSpec text of a node ('' if none). solc stores it as StructuredDocumentation {text}."""
    d = node.get("documentation")
    if d is None:
        return ""
    if isinstance(d, dict):
        return d.get("text", "") or ""
    return str(d)


def has_tag(text, tag):
    return re.search(r"@" + tag + r"\b", text) is not None


def has_param(text, name):
    return re.search(r"@param\s+" + re.escape(name) + r"\b", text) is not None


def count_returns(text):
    return len(re.findall(r"@return\b", text))


def load_asts():
    """Map absolutePath -> SourceUnit AST, deduped (each file's AST is embedded in every artifact for
    a contract declared in it). Skips build-info and any JSON without an AST."""
    asts = {}
    for art in OUT.rglob("*.json"):
        if "build-info" in art.parts:
            continue
        try:
            data = json.loads(art.read_text())
        except (json.JSONDecodeError, OSError):
            continue
        ast = data.get("ast")
        if not isinstance(ast, dict):
            continue
        ap = ast.get("absolutePath")
        if ap and ap not in asts:
            asts[ap] = ast
    return asts


def check_contract(path, group, cdef, gaps, advisories):
    """Append (member, reason) gap tuples for one ContractDefinition."""
    kind = cdef.get("contractKind", "contract")
    cname = cdef.get("name")
    label = f"{path}:{cname}"
    for m in cdef.get("nodes", []):
        nt = m.get("nodeType")
        text = doc_text(m)
        inherit = "@inheritdoc" in text

        if nt == "FunctionDefinition":
            fkind = m.get("kind", "function")
            vis = m.get("visibility")
            name = m.get("name") or f"<{fkind}>"
            if fkind != "function":
                continue  # constructors / receive / fallback exempt from the hard gate
            if vis in ("public", "external"):
                if inherit:
                    continue
                if not has_tag(text, "notice"):
                    gaps.append((label, f"function {name}()", "missing @notice"))
                for idx, p in enumerate(m.get("parameters", {}).get("parameters", [])):
                    pname = p.get("name")
                    # Skip the library `using`-receiver: the first storage-location param of a
                    # library function (e.g. `Storage storage ds`) is the receiver injected by
                    # `using L for Storage` — analogous to `self`/`this`, not a caller-facing arg.
                    if idx == 0 and kind == "library" and p.get("storageLocation") == "storage":
                        continue
                    if pname and not has_param(text, pname):
                        gaps.append((label, f"function {name}()", f"missing @param {pname}"))
                rets = m.get("returnParameters", {}).get("parameters", [])
                if rets and count_returns(text) < len(rets):
                    gaps.append((label, f"function {name}()",
                                 f"missing @return ({count_returns(text)}/{len(rets)})"))
            elif vis in ("internal", "private") and group == "A":
                # Advisory only: @dev on security-critical internals is a human judgment call.
                if not (inherit or has_tag(text, "dev") or has_tag(text, "notice")):
                    advisories.append((label, f"internal {name}()", "no @dev"))

        elif nt == "EventDefinition":
            if not inherit and not has_tag(text, "notice"):
                gaps.append((label, f"event {m.get('name')}", "missing @notice"))

        elif nt == "ErrorDefinition":
            if not inherit and not has_tag(text, "notice"):
                gaps.append((label, f"error {m.get('name')}", "missing @notice"))

        elif nt == "VariableDeclaration":
            if m.get("stateVariable") and m.get("visibility") == "public":
                if not inherit and not has_tag(text, "notice"):
                    gaps.append((label, f"public var {m.get('name')}", "missing @notice"))


def main():
    quiet = "--quiet" in sys.argv
    strict_internal = "--strict-internal" in sys.argv

    if not OUT.exists():
        print("error: out/ not found — run `forge build` first (ast = true emits the AST).")
        return 2

    asts = load_asts()

    gaps = []
    advisories = []
    missing_files = []
    n_contracts = 0

    for path, group in sorted(IN_SCOPE.items()):
        ast = asts.get(path)
        if ast is None:
            missing_files.append(path)
            continue
        for node in ast.get("nodes", []):
            if node.get("nodeType") == "ContractDefinition":
                n_contracts += 1
                check_contract(path, group, node, gaps, advisories)

    # --- report ---
    if missing_files:
        print("ERROR: in-scope files absent from build output (run `forge build`):")
        for p in missing_files:
            print(f"  - {p}")
        print()

    if gaps:
        print(f"NatSpec gaps ({len(gaps)}) — HARD GATE:\n")
        by_contract = {}
        for label, member, reason in gaps:
            by_contract.setdefault(label, []).append((member, reason))
        for label in sorted(by_contract):
            print(f"  {label}")
            for member, reason in by_contract[label]:
                print(f"      {member:<34} {reason}")
        print()
    elif not quiet:
        print("NatSpec hard gate: no gaps. ✓\n")

    if advisories and not quiet:
        print(f"Advisory ({len(advisories)}) — undocumented Group-A internal/private (review by hand,"
              " add @dev to security-critical ones):\n")
        by_contract = {}
        for label, member, reason in advisories:
            by_contract.setdefault(label, []).append(member)
        for label in sorted(by_contract):
            print(f"  {label}: {', '.join(sorted(by_contract[label]))}")
        print()

    print(f"Scope: {len(IN_SCOPE)} files ({len(GROUP_A)} A + {len(GROUP_B)} B), "
          f"{n_contracts} contract/interface/library definitions checked.")
    print(f"Hard-gate gaps: {len(gaps)} | advisory internal gaps: {len(advisories)}")

    fail = bool(gaps) or bool(missing_files) or (strict_internal and bool(advisories))
    return 1 if fail else 0


if __name__ == "__main__":
    sys.exit(main())
