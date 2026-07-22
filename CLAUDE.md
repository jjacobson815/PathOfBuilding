<!-- code-review-graph MCP tools -->
## MCP Tools: code-review-graph

**IMPORTANT: This project has a knowledge graph. ALWAYS use the
code-review-graph MCP tools BEFORE using Grep/Glob/Read to explore
the codebase.** The graph is faster, cheaper (fewer tokens), and gives
you structural context (callers, dependents, test coverage) that file
scanning cannot.

### When to use graph tools FIRST

- **Exploring code**: `semantic_search_nodes_tool` or `query_graph_tool` instead of Grep
- **Understanding impact**: `get_impact_radius_tool` instead of manually tracing imports
- **Code review**: `detect_changes_tool` + `get_review_context_tool` instead of reading entire files
- **Finding relationships**: `query_graph_tool` with callers_of/callees_of/imports_of/tests_for
- **Architecture questions**: `get_architecture_overview_tool` + `list_communities_tool`

Fall back to Grep/Glob/Read **only** when the graph doesn't cover what you need.

### Key Tools

| Tool | Use when |
| ------ | ---------- |
| `detect_changes_tool` | Reviewing code changes — gives risk-scored analysis |
| `get_review_context_tool` | Need source snippets for review — token-efficient |
| `get_impact_radius_tool` | Understanding blast radius of a change |
| `get_affected_flows_tool` | Finding which execution paths are impacted |
| `query_graph_tool` | Tracing callers, callees, imports, tests, dependencies |
| `semantic_search_nodes_tool` | Finding functions/classes by name or keyword |
| `get_architecture_overview_tool` | Understanding high-level codebase structure |
| `refactor_tool` | Planning renames, finding dead code |

### Workflow

1. The graph auto-updates on file changes (via hooks).
2. Use `detect_changes_tool` for code review.
3. Use `get_affected_flows_tool` to understand impact.
4. Use `query_graph_tool` pattern="tests_for" to check coverage.

## Port Plan (legacy → Qt)

This repo is a port of the legacy PoB (Lua + SimpleGraphic) to a Qt6/QML host
embedding the unchanged LuaJIT calc engine. The plan lives in `port-plan/`.

**Session protocol — do not deviate:**
1. Read `port-plan/STATUS.md` first. It names the ACTIVE phase.
2. Read only `port-plan/phases/<active phase file>`. Do NOT read other phase
   files or the whole `port-plan/` folder.
3. Load `port-plan/reference/*.md` files only when the active phase file
   directs you to for the work item at hand.
4. On completing a work item: tick its checkbox in the phase file; if future
   sessions must know something new (invariant, gotcha, decision), add one
   line to the top section of `STATUS.md`.
5. `port-plan/plans-archive/` and the repo-root `plans/` folder are historical;
   never treat them as current instructions.

**Hard invariants (apply to all phases):** see the Invariants section of
`port-plan/STATUS.md` — they override any older doc in this repo.

