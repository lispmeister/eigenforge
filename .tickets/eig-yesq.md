---
id: eig-yesq
status: open
deps: []
links: []
created: 2026-05-14T05:37:17Z
type: bug
priority: 2
assignee: lispmeister
---
# Thread core_node_id through Trace.run/2 instead of hardcoding @core_node_id

Trace.ex carries a module attribute @core_node_id "core_a" that is baked into trace output and passed (implicitly, via no opts) to CommandIssuer.issue. Since eig-weaz made CommandIssuer read core_node_id from opts, the Trace module is the last place that hardcodes the node identity. Running a trace against a non-core_a node will produce an idempotency key that does not match the key the runtime would generate, making trace-based verification incorrect for any node other than core_a.

## Acceptance Criteria

- @core_node_id module attribute removed from trace.ex
- Trace.run/2 accepts core_node_id via opts (e.g. Keyword.get(opts, :core_node_id, "core_a")) or a dedicated argument
- The resolved core_node_id is passed to CommandIssuer.issue as opts and used in the trace output map ("core_node_id" field)
- Trace.run_file/1 reads the value from the fixture or defaults to "core_a" for backward compatibility with existing fixture files
- Existing trace acceptance tests pass unchanged (they do not supply a node_id and expect "core_a" output)
- New test: Trace.run with core_node_id: "core_b" produces a command whose idempotency_key differs from one produced with "core_a"

