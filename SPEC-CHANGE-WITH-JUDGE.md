**1. Updated OODA Diagram (IO-as-Judge TMR variant)**

Here is the control flow rewritten in the exact textual style of the original V1 spec, now adapted for the IO node as the judge:

```
outside world
  → IO live observation (PubSub stream to all cores)
  → [three identical cores running in parallel]
       → core OODA loop
            → reasoner (threshold evaluation)
            → actuator-state gate (idempotency suppression)
            → capability check
            → policy decision
       → signed proposal (action or no-action)
  → eigenforge_mailbox (proposals only)
  → IO Node (Judge)
       → collect three signed proposals
       → 2-of-3 majority vote on normalized outcome
       → if quorum: execute actuator (at most once via idempotency_key)
       → publish single after-action event + quorum evidence
  → all cores
       → append quorum_finalized event (with vote references) to local SQLite ledger
```

This replaces the original V1 chain (`core OODA → consensus/finalization boundary inside core → local ledger → signed command envelope → IO execution → core-authored after-action`).

The three cores stay **purely symmetric proposers**. No rotating finalizer, no command issuance from any core.

**2. Step-by-step instructions to update the spec**

Make these targeted edits to `PROTOTYPE-V1-SPEC.md`. Each change preserves every existing invariant (INV-01/02/03), field shape, and golden-trace compatibility while moving the judge.

1. **Update the V2 TMR description (section “Deferred V2/V3 Work” or equivalent)**  
   Replace every mention of “rotating finalizer”, “command issuance to the rotating finalizer”, and “finalizer_core_node_id” with:  
   “V2 moves the finalization/judge boundary entirely into eigenforge_io. Cores only emit signed proposals. IO performs 2-of-3 voting and executes directly.”  
   *Rationale*: Removes all privileged-core logic; matches the user-requested design and keeps V1 → V2 migration trivial (same consensus_decision_id and quorum_ref fields).

2. **Add a new subsection under “Command Envelopes And Delivery”**  
   Insert:  
   “In V2 IO-as-Judge mode, cores no longer emit command_envelopes. They emit signed_proposal messages containing the normalized action/no-action, idempotency_key, and vote signature. IO becomes the sole issuer of actuator commands.”  
   *Rationale*: Clarifies the new message type; prevents any future confusion about where execution authority lives.

3. **Update “Reasoner, Control Rule, And OODA Loop”**  
   Add one sentence at the end of the OODA paragraph:  
   “In V2 the OODA loop ends with a signed proposal sent to eigenforge_mailbox; the consensus/finalization boundary now lives inside eigenforge_io.”  
   *Rationale*: Keeps the core OODA code path 100 % unchanged while documenting the boundary shift.

4. **Update “Local Core Ledger And Integrity” and invariants**  
   Change the description of `command_envelope_issued` to `proposal_submitted` + later `quorum_finalized` (authored by IO).  
   Add to INV-01: “IO never executes without a quorum certificate attached to the after-action event.”  
   *Rationale*: Maintains the durability guarantee (INV-01) while moving the ledger write of the final decision to after IO’s vote.

5. **Update acceptance criteria / test rigs**  
   Replace “rotating finalizer + quorum certificate” with:  
   “IO-as-judge + quorum evidence attached to every after-action event; fault-injection rig must prove that killing any single core still produces correct actuator change and identical ledger entries on surviving nodes.”  
   *Rationale*: Aligns test fixtures and golden traces with the new flow; no new test complexity.

6. **Add one new note under “Split-brain safety rules”**  
   “IO enforces the 2-of-3 rule: if fewer than two valid proposals arrive for a given consensus_decision_id, IO logs a fault and takes no action. Cores remain observers only.”  
   *Rationale*: Keeps the same network-partition safety as the original V2 plan, just enforced at the IO boundary.

Total diff is < 15 lines. Everything else (contracts, schemas, PubSub topics, idempotency, golden traces) is untouched.

**3. Why locating the Judge inside the IO node makes the design more robust**

- **Perfect core symmetry** — All three cores are now byte-for-byte identical with zero election logic, zero “who is finalizer” state, and zero risk of split-brain on finalizer selection. This eliminates an entire class of bugs that the original rotating-finalizer design would have introduced.

- **Single, well-defined trust boundary** — IO is already the only process that talks to real hardware (fans, relays, Home Assistant). Placing the vote there keeps policy/decision logic out of the actuator path while making the judge the natural “last line of defense.” If IO ever sees <2 proposals it simply refuses to act — exactly the fail-safe behavior we want at the hardware edge.

- **Simpler fault isolation and recovery** — A crashed or partitioned core only affects its own proposal; the other two + IO still reach consensus and execute. IO failure is immediately visible (no actuator movement) and can be mitigated later by duplicating IO if needed. No core ever needs catch-up logic to become a finalizer.

- **Easier implementation & testing** — Voting code lives in one place (IO) instead of distributed across cores. Golden-trace tests become trivial: feed proposals, assert actuator call + identical ledger entries. This matches real aviation/rocket TMR patterns where the actuator controller (not the reasoning computers) does the final vote.

- **No loss of TMR guarantees** — We still have three independent reasoners, 2-of-3 voting, and per-core ledgers. The only trade-off is that IO is a single point for execution (acceptable for a prototype; can be TMR’d later).

This variant is strictly simpler, more maintainable, and more robust than the rotating-finalizer approach while staying faithful to the original spec’s TMR intent.


