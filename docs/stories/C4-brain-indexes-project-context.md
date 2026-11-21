# C4: the brain indexes each project's context

Status: Ready for development (2026-11-21). Risk: low.
Owner's decision (2026-11-21, ADR 0004): project context stays in each project's repo; ade-brain indexes it read-only.
Verification command: `bash tests/run.sh`.

## Goal
`bin/brain index` also reads `.ade/context/**` and `.ade/knowledge/**` (Markdown) from every code checkout listed in a
folder's ACCESS.md, so "what did we decide about X in project Y" is answered from the brain. It never writes to a checkout.

## Acceptance criteria (`tests/test_brain.sh`, fake Ollama as today)
| AC | Criterion | Test |
|---|---|---|
| 1 | A checkout's `.ade/context/decisions/0001-x.md` is indexed and found by `bin/brain search` | `project_decision_indexed` |
| 2 | `.ade/knowledge/*.md` is indexed too | `project_knowledge_indexed` |
| 3 | Results name the folder and the checkout path, e.g. `projects/demo: demo-code/.ade/context/...` | `results_name_project` |
| 4 | Nothing else in the checkout is indexed (code, `docs/`, other dot-folders) | `only_ade_folders` |
| 5 | A missing or unreadable checkout is skipped without failing the run | `missing_checkout_skipped` |
| 6 | The checkout is unchanged after indexing (no file written, mtimes kept) | `checkout_untouched` |
| 7 | A removed decision file drops out of the index on the next run | `removed_file_dropped` |
