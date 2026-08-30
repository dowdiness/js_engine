# Is a Cohort Lock required before cross-engine measurement?

**Status:** research reassessment of ADR 0028; not a decision record

## Short answer

No. A separate, content-addressed `Cohort Lock` file is not required before
this project can start a credible cross-engine measurement experiment.

What is required is smaller: a reviewer must be able to identify the exact
measurement definition, the exact resolved inputs, and the facts of the run.
The current repository already pins most external inputs in the four probe
specifications and verifies the JetStream revision and engine payload digest at
execution time. A new lock file that copies those values would add a second
source of truth before it protects an additional risk.

The recommended next step is therefore an A/A prototype using one checked-in
measurement-definition file. The prototype should emit an evidence record that
names the definition by repository commit, path, and SHA-256 of its exact
bytes; it should also record resolved inputs and runner facts. Promote that
definition to a separately named, content-addressed cohort document only if
the prototype demonstrates a real need to exchange it independently of the
repository revision, to sign it, or to reuse it across repositories.

This changes the immediate implementation order in ADR 0028. It does not
weaken the eventual publication contract: a published result still needs
complete inputs, raw repetitions, correctness evidence, and calibration.

## The problem to solve

Two questions are easily confused:

1. *Can a later reader reproduce what was requested?* This needs a stable
   measurement definition and resolved dependency identities.
2. *Can a reader trust a particular execution?* This needs run provenance,
   raw outputs, and a validation/calibration policy.

A lock file can help with the first question. It cannot make a noisy hosted
runner stable, prove that every engine ran, or turn a diagnostic timing into a
publishable comparison. Those are properties of the run and its evidence.

SLSA makes the same distinction: its provenance model separates a stable
`buildDefinition` (parameters and resolved dependencies) from `runDetails`
(the builder and a particular invocation). That model deliberately avoids
overly rigid input categories because they made provenance harder to apply in
real systems. [SLSA Build Provenance](https://slsa.dev/spec/v1.2/build-provenance)
and [its v1.0 rationale](https://slsa.dev/spec/v1.0/whats-new) are useful
precedents, even though a performance measurement is not a software release.

For this project, the stable definition includes the selected JetStream
revision/workload, member order, shell command configuration, correctness
requirements, and intended profile. Resolved inputs include the acquired
engine payload digest and the actual executable version. Run facts include the
workflow run, runner image, operating system, architecture, timestamps,
schedule, repetitions, and raw results.

## Evidence from the current repository

The existing external-engine probe specifications already contain a generation,
JetStream commit, workload, exact `jsvu` version, exact engine version,
relative executable, and payload SHA-256. For example, see the
[V8 specification](../../scripts/jetstream3_v8_probe.json). The common probe
implementation rejects a changed JetStream revision, a dirty checkout, or a
payload fingerprint mismatch before it runs the workload:
[reference probe core](../../scripts/jetstream3_reference_probe_core.js).

The probe report additionally records environment facts and explicitly labels
its timings diagnostic-only. The admission workflow preserves the reports as
artifacts, but they expire after 90 days:
[admission workflow](../../.github/workflows/jetstream3-admission.yml).

This means that the information a first manifest would copy is already
repository-controlled and checked at the execution boundary. The missing
evidence is not primarily a digest of a new document. It is a single-job
measurement execution that records all candidate results and tells us whether
the hosted environment is stable enough for publication.

JetStream supports this ordering. It owns its workload timing, scoring, and
correctness behavior; scores from different JetStream versions are not
comparable. [JetStream 3 in-depth analysis](https://browserbench.org/JetStream/in-depth.html)
therefore makes the pinned revision essential, but does not require a separate
project-specific lock-file format.

## Options considered

| Option | What it proves | Essential benefit now | Cost and failure mode | Decision |
| --- | --- | --- | --- | --- |
| 1. Standalone content-addressed Cohort Lock | A custom manifest names a cohort by digest. | A portable identifier independent of a Git revision. | Duplicates probe fields, needs schema, canonicalization, validation, fixtures, migration policy, and rules for two conflicting sources of truth. A digest alone does not attest to execution. | Defer. |
| 2. Hash exact checked-in definition bytes | A result refers to one human-readable repository file exactly. | One source of truth; a cheap, direct integrity check. Git commit/path already locate the reviewed definition. | Whitespace changes alter the digest; this is desirable for a first contract because it exposes every change. | Adopt for the prototype. |
| 3. Workflow/run provenance only | A workflow identifies its checkout and run environment. | Captures the particular execution and can link artifacts to CI. | Cannot by itself say which external payload was acquired or which parameters were intended; workflow edits and mutable actions can change meaning. | Insufficient alone. |
| 4. A/A prototype before final schema | Repeated identical executions measure host and harness variability. | Directly tests whether the proposed publication medium is usable and identifies which fields the runner truly needs. | Does not itself provide a long-term public dataset. | Do first. |

### Why exact bytes are sufficient initially

The prototype definition should be a normal checked-in JSON file (or another
format already supported by the runner), not a generated lock file. The runner
copies its exact bytes into the evidence artifact or records their SHA-256,
repository commit, and repository-relative path. Including the bytes removes
any dependency on later Git retention or hash-algorithm details; including the
digest makes accidental artifact corruption visible.

If the project later needs a digest invariant under harmless JSON formatting,
RFC 8785 defines the JSON Canonicalization Scheme (JCS): deterministic property
sorting and an invariant, hashable JSON representation. It is an appropriate
standard *then*, not a reason to introduce canonicalization now. JCS itself
exists for cryptographic hashing/signing of JSON objects, whereas the prototype
only needs to identify the reviewed bytes.
[RFC 8785](https://www.rfc-editor.org/rfc/rfc8785.html).

The distinction matters: byte hashing is a small integrity convention; JCS is
an interoperability feature with I-JSON constraints and a second serializer
whose behavior must be tested and maintained. Neither changes experimental
validity.

### Why workflow provenance is necessary but insufficient

GitHub Actions can attest artifacts and bind them to a repository, commit,
workflow, and triggering event. Its official guidance also says attestations
are for release artifacts or manifests containing content hashes, not frequent
automated-test outputs. [GitHub artifact attestations](https://docs.github.com/en/actions/concepts/security/artifact-attestations)
and [their build-provenance guide](https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/use-artifact-attestations)
therefore support retaining ordinary raw measurement artifacts first, rather
than making signing a prerequisite for calibration.

The workflow must still record ephemeral facts that a checked-in definition
cannot know in advance: the actual runner image, OS/architecture, acquisition
outputs, schedule, timestamps, and raw per-repetition results. GitHub-hosted
runners are fresh virtual machines and runner images can change; their labels
describe an environment class rather than one permanent machine.
[GitHub-hosted runners](https://docs.github.com/en/actions/concepts/runners/github-hosted-runners#runner-images).

## What makes A/A the right first experiment

The first decision is whether measurements from the planned GitHub-hosted
single-job setup are stable enough to publish at all. Running the same complete
definition repeatedly answers that directly. It is more informative than
designing a complete cohort schema in advance because it exposes the real
execution boundaries: acquisition variability, runner drift, command-line
differences, result serialization, and artifact size.

Mozilla's performance tooling retains multiple replicates rather than reducing
each task to one summary value; its documentation distinguishes the replicate
data from the task summary. [Firefox Mach Try Perf workflow](https://firefox-source-docs.mozilla.org/testing/perfdocs/standard-workflow.html)
also demonstrates that repeat structure is part of evidence, not merely a
dashboard detail. Its Talos documentation distinguishes row-major and
column-major repetition orders to improve stability. [Talos performance
testing](https://firefox-source-docs.mozilla.org/testing/perfdocs/talos.html).

The prototype should be deliberately bounded: run the same small cohort twice
under the intended job shape, preserve every raw result, and report spread. It
must make no regression claim and should reject a run whose official workload
oracle fails. If the two runs demonstrate unusable variation, stop; a Cohort
Lock would not repair that problem.

## Smallest reproducible contract

For the prototype, add one checked-in **measurement definition** only when the
runner is added. It should reference, rather than repeat, the existing engine
probe specifications. The definition needs only:

- a schema version and ordered eligible candidate IDs;
- one JetStream commit and workload identity;
- the repository-relative paths and SHA-256 values of the selected probe
  specifications;
- the command profile, timeout, repetitions, and execution-order rule; and
- the official correctness/result contract version.

At runtime, emit one **measurement evidence record** containing:

- the definition bytes or their SHA-256, path, and source commit;
- the resolved engine payload hashes and observed engine versions;
- runner image, OS, architecture, workflow run identity, and timestamps;
- the actual command/schedule and every raw structured result; and
- validity, calibration summary, and failures without a derived ranking.

The definition names intent. The evidence record names what occurred. Keeping
them separate is the useful part of the earlier Cohort Lock idea, without
requiring a new abstraction to be independently versioned and content-addressed.

## Revised implementation order

1. **Write the smallest one-job A/A prototype.** It reads the existing pinned
   probe specifications, runs admitted candidates together, retains raw
   results, and produces the measurement evidence record. Do not publish a
   dashboard value.
2. **Measure and inspect two or more identical rounds.** Check correctness,
   completion, variation, artifact size, and whether the evidence actually
   permits a reviewer to rerun the same inputs.
3. **Add only the missing definition fields.** Introduce one checked-in
   measurement definition if the prototype cannot unambiguously identify its
   inputs from the existing specs and workflow. Hash its exact bytes in every
   evidence record.
4. **Add balanced scheduling and bounded A/A calibration.** These are needed
   before publication, because they address experimental validity rather than
   metadata completeness.
5. **Decide whether an independent Cohort Lock is justified.** Do so only if a
   definition must be distributed outside Git, signed, referenced by several
   repositories, or made formatting-insensitive. At that point use a standard
   canonicalization scheme such as JCS and keep the lock as the only source of
   locked fields.
6. **Publish a dataset/dashboard category after calibration.** Persist both the
   definition and evidence; derive any same-round ratio or ordering at display
   time.

## Recommendation

Replace the immediate "implement Cohort Lock manifest" task with a
measurement-only A/A prototype and an exact-bytes provenance convention. This
is the smallest contract that can reveal whether hosted cross-engine evidence
is publishable. It preserves the important discipline—pinned inputs, raw
results, correctness validation, and explicit run provenance—while avoiding a
new schema, canonicalizer, and duplicate lock data before their benefits are
demonstrated.

If later evidence shows that the definition must travel independently of this
repository, promote the existing checked-in definition into a real Cohort Lock
rather than maintaining both forms. That is a reversible, evidence-driven
path to the same long-term capability.
