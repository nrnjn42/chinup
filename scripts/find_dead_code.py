"""Cross-reference every declaration in the symbol graph against textual usage.

Declarations come from `swiftc -emit-symbol-graph` (AST-derived, so the name and
source location are exact). Usage counting is textual because Swift symbol graphs
carry no call edges. Candidates still need a human read -- this narrows 2k lines
to a handful, it does not prove deadness.
"""

import json
import re
import sys
from collections import defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SRC = REPO / "src" / "ChinUp"

# Names the compiler or SwiftUI calls for you; absence of a textual reference
# says nothing about whether they are live.
PROTOCOL_MEMBERS = {
    "body", "init", "deinit", "shared", "id", "hashValue", "description",
    "makeUIViewController", "updateUIViewController", "makeCoordinator",
    "rawValue", "allCases", "path", "animatableData",
}

SKIP_KINDS = {
    "swift.extension",
    "swift.protocol.requirement",
}


def load_symbols(sg_path: Path) -> list[dict]:
    data = json.loads(sg_path.read_text())
    return data.get("symbols", [])


def swift_files() -> list[Path]:
    return sorted(SRC.rglob("*.swift"))


def main() -> int:
    sg = Path(sys.argv[1])
    symbols = load_symbols(sg)

    sources = {p.resolve(): p.read_text().splitlines() for p in swift_files()}

    findings: dict[str, list[tuple[int, str, str, int]]] = defaultdict(list)

    for sym in symbols:
        kind = sym.get("kind", {}).get("identifier", "")
        if kind in SKIP_KINDS:
            continue

        name = sym.get("names", {}).get("title", "")
        if not name:
            continue
        # Enum cases arrive qualified ("Quality.good"); keep the leaf.
        # Methods carry argument labels ("pauseSession(duration:reason:)"); drop them.
        base = name.split(".")[-1].split("(")[0]
        if not base.isidentifier() or base in PROTOCOL_MEMBERS:
            continue

        loc = sym.get("location", {})
        uri = loc.get("uri", "")
        decl_line = loc.get("position", {}).get("line", -1)
        if not uri.startswith("file://"):
            continue
        # The graph emits paths relative to the invocation directory, not absolute.
        decl_path = (REPO / uri[len("file://"):]).resolve()
        if decl_path not in sources:
            continue

        pattern = re.compile(rf"\b{re.escape(base)}\b")
        uses = 0
        for path, lines in sources.items():
            for i, line in enumerate(lines):
                if path == decl_path and i == decl_line:
                    continue
                uses += len(pattern.findall(line))

        if uses == 0:
            findings[str(decl_path.relative_to(REPO))].append(
                (decl_line + 1, base, kind.replace("swift.", ""), uses)
            )

    if not findings:
        print("No zero-reference declarations found.")
        return 0

    total = 0
    for path in sorted(findings):
        print(f"\n{path}")
        for line, base, kind, _ in sorted(findings[path]):
            print(f"  :{line:<4} {kind:<22} {base}")
            total += 1
    print(f"\n{total} zero-reference declarations")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
