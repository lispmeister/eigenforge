# Specification Systems Survey

Date: 2026-05-18

## Question

Eigenforge and Aether have so far used Markdown specifications such as
`AETHERLANG-004.md` and `PROTOTYPE-V1-SPEC.md`. While reading Nancy Leveson's
_Engineering a Safer World_, we identified a possible need for a more
AI-first specification language.

The desired system is not just a low-level formal method for algorithms, such
as TLA+, Lean, Dafny, or Coq. The target is a specification language or
specification system that can:

- Describe a system iteratively, with each round adding more detail.
- Preserve traceability from high-level intent down toward implementation.
- Define contracts between components.
- Support deep algorithmic proofs where necessary.
- Remain friendly to AI coding assistants and repo-native development.

## Summary

No single mature language appears to fully match this target.

The closest conceptual match is Leveson's own family of work around intent
specifications and SpecTRM-RL. The closest current AI-agent tooling is the
emerging family of spec-driven development workflows such as GitHub Spec Kit,
OpenSpec, and Kiro-style specs. Those newer tools are useful, but they are
mostly structured Markdown workflows rather than formally grounded
specification languages.

The most promising direction appears to be a layered specification system that
composes existing approaches under one traceability model.

## Strongest Matches

### Intent Specifications and SpecTRM-RL

Intent specifications are the strongest philosophical match. They organize a
system by layers of "why", "what", and "how", tracing from high-level purpose
and constraints down toward design and implementation.

SpecTRM-RL was designed for safety-critical control systems. It focuses on
black-box behavioral requirements, completeness, safety constraints, and
models that can be analyzed or executed where appropriate.

Relevant reference:

- <https://www.researchgate.net/publication/3922788_An_intent-specifications_model_for_a_robotic_software_control_system>

Assessment: this is the closest known precedent for an iterative,
intent-preserving, safety-oriented specification system. It is not AI-first,
but it has the right conceptual shape.

### NASA FRET and FRETish

NASA FRET provides a controlled natural language for requirements, called
FRETish. It lets users write structured requirements with unambiguous
semantics and can translate them into temporal logic and analysis artifacts.

Relevant reference:

- <https://software.nasa.gov/software/ARC-18066-1>

Assessment: FRET is highly relevant for the "controlled natural language that
can become formal" part of the problem. It is not a complete whole-system
specification language, but it could be a useful layer inside one.

### SysML v2 and KerML

SysML v2 provides textual syntax, formal semantics, requirements, constraints,
behavior, structure, and APIs for tool access. KerML is the underlying
kernel/modeling language.

Relevant reference:

- <https://sysml.org/sysml-specs/>

Assessment: SysML v2 may be the most serious existing substrate for layered,
traceable system specifications. It is rooted in model-based systems
engineering rather than AI coding, and it may be heavier than desired for
repo-native agent workflows.

### B Method and Event-B

The B family explicitly supports refinement from abstract specifications
toward implementable models, with proof obligations at each refinement step.
Event-B is especially associated with system-level modeling and incremental
refinement.

Relevant references:

- <https://www.labri.fr/perso/sutre/Teaching/B/>
- <https://www.atelierb.eu/en/presentation-of-the-b-method/raffinement-automatique-copy/>

Assessment: this family matches the "each round getting closer to the machine"
requirement better than most modern AI-spec tools. It is less naturally suited
to broad product, system, or agent-readable specification documents.

### AADL

The Architecture Analysis and Design Language is used for architecture,
components, runtime behavior, embedded systems, timing, faults, reliability,
and safety analysis.

Relevant reference:

- <https://www.sei.cmu.edu/library/architecture-analysis-and-design-language-aadl-tool/>

Assessment: AADL is relevant for component interfaces, architecture,
deployment, timing, and safety properties. It is not primarily an AI-first
specification language, but it could inform the architecture and contract
layers.

## AI Coding Assistant Spec Workflows

These systems are closer to current AI coding practice, but they are generally
less formal than the target described above.

### GitHub Spec Kit

GitHub Spec Kit supports a spec-driven development workflow for AI coding
agents: specification, plan, tasks, and implementation. It includes the idea of
a project constitution.

Relevant reference:

- <https://github.github.com/spec-kit/index.html>

Assessment: strong workflow precedent for agentic development, but not a
formal specification language.

### OpenSpec

OpenSpec uses repo-local specs, proposed changes, and archived decisions to
maintain living documentation for AI-assisted development.

Relevant reference:

- <https://thedocs.io/openspec/>

Assessment: useful for lifecycle and change-management patterns, but not a
deep formal or safety-oriented language.

### Kiro Specs

Kiro feature specs use requirements, design, and task documents. The workflow
often uses EARS-style requirements.

Relevant reference:

- <https://kiro.dev/docs/specs/feature-specs/>

Assessment: relevant for practical AI-assisted software development, but still
mostly structured prose.

### MAP Spec

MAP Spec proposes a YAML-like structure for AI-readable software
specifications across metadata, functional requirements, APIs, data, UI,
business rules, and quality concerns.

Relevant reference:

- <https://mapspec.io/>

Assessment: interesting as an early AI-readable contract format. It appears
much less mature than established systems-engineering or formal-methods
approaches.

## Adjacent Formal and Semi-Formal Tools

These do not solve the whole problem, but they contain useful pieces.

### Quint

Quint is a modern specification language in the TLA+ family, with attention to
tooling and executable specifications.

Reference:

- <https://quint.sh/>

Use: distributed systems, protocols, state machines, executable models.

### Dafny, Why3, JML, and ACSL

These support code-near contracts, verification conditions, and proofs.

References:

- <https://dafny.org/dafny/DafnyRef/DafnyRef>
- <https://www.why3.org/>
- <https://www.cs.ucf.edu/~leavens/JML/jmlkluwer/jmlkluwer_1.html>

Use: component contracts, invariants, preconditions, postconditions,
algorithmic correctness, and implementation-adjacent proof.

### Alloy and Clafer

Alloy and Clafer support lightweight modeling of structures, relations, and
constraints.

References:

- <https://people.csail.mit.edu/edmond/research/alloy-modelling.html>
- <https://www.clafer.org/p/about.html>

Use: finding contradictions or counterexamples in structural models,
configuration spaces, authorization models, and domain constraints.

### Gherkin, EARS, and Design by Contract

These provide useful syntax patterns for executable examples, constrained
requirements, and interface contracts.

References:

- <https://cucumber.io/docs/gherkin/reference>
- <https://research.manchester.ac.uk/en/publications/easy-approach-to-requirements-syntax-ears>
- <https://www.eiffel.com/values/design-by-contract/introduction/>

Use: testable requirements, acceptance criteria, scenario examples,
preconditions, postconditions, and invariants.

## Candidate Architecture for an Eigenforge/Aether Specification System

A practical AI-first specification system could compose existing ideas rather
than invent every layer from scratch.

Potential layers:

1. Intent and purpose layer
   - Inspired by Leveson's intent specifications.
   - Captures system purpose, hazards, losses, constraints, stakeholders, and
     rationale.

2. Control and safety layer
   - Inspired by STAMP/STPA.
   - Captures control structures, unsafe control actions, process models,
     feedback, and safety constraints.

3. Requirements layer
   - Inspired by FRETish and EARS.
   - Uses controlled natural language for requirements that can be checked,
     transformed, or linked to formal artifacts.

4. Architecture and component layer
   - Inspired by SysML v2 and AADL.
   - Captures components, ports, messages, state ownership, resources,
     deployment, timing, and fault assumptions.

5. Contract layer
   - Inspired by Design by Contract, JML, ACSL, Dafny, and Why3.
   - Captures assumptions, guarantees, invariants, preconditions,
     postconditions, failure modes, and compatibility checks.

6. Formal model layer
   - Uses TLA+, Quint, Event-B, Alloy, Lean, Dafny, or another specialized
     tool only where the added rigor is worth the cost.

7. Agent workflow layer
   - Inspired by GitHub Spec Kit, OpenSpec, and Kiro.
   - Defines how AI coding assistants consume specs, propose plans, generate
     tasks, modify code, verify acceptance criteria, and update the spec.

## Design Implications

The likely opportunity is not "replace Markdown with a formal language".

The opportunity is to define a repo-native specification stack where Markdown
or another readable text format remains the carrier, but each section has
machine-readable structure, typed references, stable identifiers, and optional
links to formal artifacts.

Important design properties:

- Stable identifiers for every claim, requirement, constraint, component,
  interface, assumption, and proof artifact.
- Explicit trace links between levels.
- Versioned refinement steps rather than overwritten prose.
- A distinction between intent, requirement, design decision, implementation
  contract, test, and proof.
- Agent-readable task boundaries and acceptance checks.
- Support for partial formalization: most of the system can remain structured
  prose, while high-risk or high-leverage parts receive deeper formal models.
- Bidirectional workflow: specs guide code, and implementation discoveries can
  propose spec updates.

## Open Questions

1. Should the target system cover software-only systems, cyber-physical control
   systems, or both?
2. Should the primary authoring format remain human-readable text files in git?
3. Should the first prototype optimize for AI coding agents, safety analysis,
   or formal verification hooks?
4. Should Eigenforge define a new language, or a profile that composes existing
   languages under one traceability model?
5. What is the smallest useful vertical slice: requirements-to-tests,
   hazards-to-constraints, component contracts, or refinement-to-code?

## Provisional Conclusion

The desired tool does not appear to exist as a mature, integrated system.

The nearest existing conceptual ancestor is Leveson's intent specification
work. The nearest practical agentic workflow ancestors are GitHub Spec Kit,
OpenSpec, and Kiro-style specs. The most credible path is a new layered
specification system that treats AI coding assistants as first-class consumers
while preserving traceability, refinement, contracts, and optional deep formal
verification.
