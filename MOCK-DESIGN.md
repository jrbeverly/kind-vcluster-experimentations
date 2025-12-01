# Mock Design

## Purpose

This document is a high-level mock design for the experimentation platform described in [PROBLEM.md](PROBLEM.md), [TECHNICAL.md](TECHNICAL.md), and [VISION.md](VISION.md).

It is intentionally conceptual. It is meant to answer:

- Is the overall system implementable?
- Do the proposed components fit together coherently?
- Where are the major risks, ambiguities, and decision points?
- What structure would support meaningful experimentation without prematurely fixing low-level design details?

This is not a production architecture and not a detailed implementation specification.

## Executive Assessment

The proposed system is fundamentally implementable.

The strongest version of the idea is not "build the best vCluster platform" but "build a repeatable topology lab for comparing vCluster architectural patterns." Framed that way, the repository direction is coherent and realistic.

The concept is most viable if it is treated as:

- An experimentation harness
- A topology comparison framework
- A repeatable local testbed
- A place to capture operational findings, including failed experiments

The biggest conceptual risk is not that vCluster or local Kubernetes cannot do this. The biggest risk is that the experiments remain too ambiguous to compare meaningfully. Right now, the repository clearly defines the questions, but it does not yet define the comparison method well enough.

## Core Reading of the Intent

Across the three source documents, the repository is trying to answer four related questions:

1. Where should shared infrastructure live?
2. How thin can the host cluster realistically become?
3. When does it make sense to separate infrastructure and application concerns across multiple physical clusters?
4. What management boundary feels operationally natural: direct vCluster control, host-mediated control, or hybrid models?

That intent is consistent across the source documents and is conceptually sound.

## High-Level Conclusion

### What is viable

- A local, disposable experimentation platform based on Kubernetes host clusters and vClusters
- Comparative experiments across at least three topology families
- Direct and indirect management of vClusters
- Cross-cluster experiments using multiple local Kubernetes clusters
- Repeatable setup and teardown workflows

### What is only conditionally viable

- Running "shared infrastructure" inside dedicated infrastructure vClusters as a general pattern
- Treating the host cluster as almost responsibility-free
- Expecting all infrastructure categories to behave naturally inside virtual clusters

### Why the conditionality matters

vCluster is a real Kubernetes control plane experience, but it is still layered on top of a host cluster. The host cluster remains the ultimate substrate for scheduling, networking, storage, and access exposure. That means "minimal host cluster" is a useful experimental direction, but not an absolute state. Some responsibilities cannot be fully virtualized away.

## Design Principles

The platform should be designed around these principles:

- Experimentation first, not production hardening
- Comparable scenarios over one-off demos
- Disposable environments over long-lived state
- Explicit boundaries over implicit convenience
- Findings capture as a first-class concern
- Minimal commitment to one topology too early

## Working Assumptions

These assumptions are reasonable based on the repository intent and current state:

- `kind` should be the primary local substrate because the repository is explicitly kind-oriented and local reproducibility matters.
- Other local Kubernetes runtimes may be added later, but they should not drive the initial design.
- The baseline should assume open, locally runnable workflows without requiring devcontainer usage.
- The platform should not depend on advanced or product-tier-only features unless they are explicitly marked as optional experiment extensions.
- Local environments are useful for architectural validation, but they will not perfectly model cloud networking, managed storage, or production failure domains.

## Conceptual System Model

The repository should behave like a topology lab with five layers:

1. Substrate provisioning
2. Topology composition
3. Workload and infrastructure seeding
4. Experiment execution
5. Observation and results capture

Conceptually:

```text
Workstation
  -> Local cluster substrate (one or more Kubernetes clusters, kind first)
    -> Host cluster(s)
      -> vCluster instances
        -> Infrastructure workloads and/or application workloads
  -> External orchestration and experiment runner
  -> Result capture, notes, and comparison artifacts
```

The important design boundary is that orchestration should remain outside the tested topology whenever possible. The repository should create and exercise topologies, not become tightly embedded inside one of them.

## Proposed Major Components

### 1. Cluster Substrate Layer

Responsibility:

- Create one or more disposable local Kubernetes clusters
- Provide consistent baseline prerequisites for all experiments
- Reset cleanly between runs

This layer should be intentionally boring. Its purpose is to remove local-environment noise so topology differences are easier to compare.

### 2. Topology Definitions

Responsibility:

- Define the shape of each experiment
- Express where shared infrastructure lives
- Express how many physical clusters exist
- Express how vClusters are grouped and related
- Express which management path is being tested

These definitions should stay declarative at a high level. They should describe intent, not low-level mechanics.

### 3. Workload Packs

Responsibility:

- Provide representative infrastructure workloads
- Provide representative application workloads
- Give the experiments something realistic to exercise

This matters because "can this architecture work?" cannot be answered in the abstract. The platform needs at least a small set of repeatable workload types to reveal real boundary issues.

### 4. Management Plane Exercise Layer

Responsibility:

- Test direct vCluster administration
- Test host-cluster-mediated administration
- Test cross-cluster administrative coordination
- Test hybrid control paths

This should be treated as its own experiment axis, not a side effect of topology setup.

### 5. Results and Comparison Layer

Responsibility:

- Record what succeeded
- Record what failed
- Record where the friction appeared
- Make experiments comparable over time

Without this layer, the repository risks producing setups instead of knowledge.

## Candidate Topology Families

### Experiment 1: Shared Infrastructure on the Host Cluster

Intent:

- Use the host cluster as the shared platform substrate
- Keep application vClusters relatively lightweight
- Centralize common operators and shared services

Assessment:

- This is the most viable starting point.
- It is the best baseline for comparing later models.
- It minimizes sync and exposure complexity.

Main risks:

- The host cluster can become operationally heavy very quickly.
- Shared infrastructure can erode isolation goals.
- Blast radius may be larger than desired.

### Experiment 2: Infrastructure-Isolated vCluster Model

Intent:

- Move shared infrastructure into dedicated infrastructure-oriented vClusters
- Keep the host cluster thin
- Strengthen logical separation between shared systems and application environments

Assessment:

- This is viable as an experiment.
- It is not universally viable for every class of infrastructure.
- It is likely the most informative topology because it will expose where virtualization boundaries feel natural and where they fight the platform.

Main risks:

- Some operators and control-plane-adjacent tools assume cluster-scoped visibility or host-level behavior.
- Some infrastructure categories rely on networking, storage, ingress, or node-level assumptions that do not map cleanly into a virtualized boundary.
- Resource sync rules can become part of the architecture rather than just implementation detail.

Important nuance:

This model is best treated as "which infrastructure classes can be usefully isolated into vClusters?" rather than "all infrastructure should move into vClusters."

### Experiment 3: Dual-Cluster Architecture

Intent:

- Separate application-oriented and infrastructure-oriented concerns across multiple physical clusters
- Explore whether physical separation creates clearer operational boundaries

Assessment:

- Conceptually viable
- Operationally heavier
- Appropriate as a second-phase or third-phase experiment rather than the initial baseline

Main risks:

- Cross-cluster access and identity management become a real concern
- Exposure and connectivity are more complex locally than they look on paper
- The number of moving parts rises quickly, making comparisons harder unless the experiment scope stays small

## Management Boundary Models

The source documents correctly identify management flow as a core design variable.

The platform should explicitly support three modes:

### Direct vCluster Management

Management tools connect to each vCluster as its own Kubernetes API target.

Good for testing:

- Tenant-like operational models
- Strong administrative separation
- Per-vCluster access patterns

Tradeoff:

- Creates kubeconfig and credential sprawl
- Harder to manage at scale

### Host-Mediated Management

Management tools operate primarily against the host cluster and rely on vCluster sync and host-side visibility.

Good for testing:

- Centralized operator models
- Shared platform control
- Lower operational context switching

Tradeoff:

- Can blur intended isolation boundaries
- May hide tenant-facing operational reality

### Hybrid Management

Some operations are host-mediated and others connect directly to vClusters.

Good for testing:

- Realistic platform operations
- Boundary-specific decisions

Tradeoff:

- More flexible, but also easier to make inconsistent

## Critical Architectural Insight

The host cluster can become thinner, but it cannot disappear conceptually.

Even in the "minimal host" direction, the host cluster still owns or strongly influences:

- Actual workload scheduling
- Underlying network behavior
- Storage implementation
- Resource translation and sync behavior
- API exposure paths
- Security and node-level realities

That is not a flaw in the idea. It is one of the core truths the experimentation platform should help make visible.

## What the Platform Must Compare

To make results meaningful, each experiment should be evaluated against a consistent set of dimensions:

- Setup complexity
- Day-2 operational ergonomics
- Isolation clarity
- Blast radius
- Operator and CRD compatibility
- Networking and exposure friction
- Storage and persistence friction
- Cross-cluster coordination burden
- Ease of teardown and repeatability
- How much hidden host-cluster coupling remains

If these comparison dimensions are not defined early, the repository may generate many interesting setups but little durable insight.

## Proposed High-Level Repository Shape

The repository does not need a detailed implementation structure yet, but it would benefit from a clear conceptual layout such as:

- `docs/`
  High-level design notes, experiment reports, comparison summaries, and open questions
- `topologies/`
  Definitions for each architectural model and management boundary variant
- `clusters/`
  Local host-cluster substrate definitions
- `workloads/`
  Reusable infrastructure and application packs used to exercise the topologies
- `scripts/` or `tasks/`
  Setup, run, validate, and teardown orchestration
- `results/`
  Captured outputs, observations, and structured comparison artifacts

The exact naming is not important yet. The boundary between these concerns is important.

## Major Risks and Ambiguities

### 1. "Shared infrastructure" is not yet defined tightly enough

The current documents refer to operators, platform tooling, foundational services, and management systems, but these categories contain very different technical behaviors. An ingress controller, a policy engine, cert-manager, external secrets, GitOps tooling, observability stacks, and cluster-autoscaling-style tools do not impose the same architectural constraints.

This is the single biggest ambiguity in the current direction.

### 2. The comparison criteria are not yet explicit

The repository is clear about what it wants to explore, but not yet clear about how conclusions will be drawn. Without a comparison framework, later findings will be difficult to trust or reuse.

### 3. The tech stack description is partially incomplete

[TECHNICAL.md](TECHNICAL.md) contains unresolved citation placeholders in the "Core Technology Stack" section rather than a clean statement of supported local runtimes and tools. That is not a conceptual blocker, but it does leave the baseline ambiguous.

### 4. Local realism has limits

Local multi-cluster experiments are valid for architecture exploration, but not every network, ingress, storage, or identity behavior will match managed environments. The platform should treat local reproducibility as a fast validation environment, not as a perfect production emulator.

### 5. Experiment 2 may expose product or feature assumptions

Some resource-sync-heavy or CRD-heavy patterns may depend on vCluster capabilities that are nuanced, limited, or better treated as optional rather than assumed baseline behavior. The design should avoid making those features mandatory for the entire platform.

### 6. Current repo scaffolding conflicts with stated constraints

The repository contains devcontainer scaffolding even though the source documents explicitly reject devcontainer dependency. This is not a blocker if it is treated as legacy scaffolding, but the repo should eventually make that stance explicit to avoid mixed signals.

## Clarifying Questions

These questions are not blockers for this mock design, but answering them would sharpen the next iteration substantially:

1. What infrastructure classes are in scope for early experiments?
2. Is the first implementation expected to remain fully open-source-compatible, or are optional vCluster product-tier features acceptable in later experiments?
3. Is `kind` the required primary substrate, or should parity across multiple local Kubernetes distributions matter from the beginning?
4. Which result matters most: deployability, isolation quality, administrative ergonomics, resource efficiency, or comparative learning across models?
5. Should GitOps-style management be part of the experiment surface, or should the first phase stay focused on direct CLI and manifest-driven administration?
6. Is the goal to compare a small number of carefully chosen representative workloads, or to support a broad catalog of interchangeable workloads later?

## Recommended Direction

The most coherent path forward is staged:

### Stage 1

- Establish one clean local substrate
- Implement Experiment 1 as the baseline
- Add result-capture conventions
- Define comparison criteria

### Stage 2

- Introduce Experiment 2 with a deliberately small set of infrastructure categories
- Learn which infrastructure types fit well inside vClusters and which resist that model

### Stage 3

- Introduce Experiment 3 only after management flow and comparison method are stable
- Keep dual-cluster scope intentionally narrow at first

This sequence reduces ambiguity without collapsing the experimentation space too early.

## Final Viability Statement

Yes, the overall system is conceptually viable.

It will work best if it is built as an experimentation framework for comparing topology patterns, not as an attempt to prove that one universal virtual-cluster architecture should exist.

The main blockers are not foundational technology blockers. They are design-clarity blockers:

- Define what counts as shared infrastructure
- Define how experiments will be compared
- Define which management boundaries are first-class
- Keep the host-cluster reality visible rather than abstracting it away too aggressively

If those are handled explicitly, the proposed components fit together coherently and the repository can become a useful architecture research sandbox.

## Reality Check References

These references support the viability assessment and the cautions around local operation and vCluster boundary behavior:

- kind quick start: https://kind.sigs.k8s.io/docs/user/quick-start/
- kind known issues: https://kind.sigs.k8s.io/docs/user/known-issues/
- vCluster overview: https://www.vcluster.com/docs/vcluster/#deploy-vcluster
- vCluster sync model: https://www.vcluster.com/docs/vcluster/configure/vcluster-yaml/sync/
- vCluster host-node behavior: https://www.vcluster.com/docs/vcluster/deploy/worker-nodes/host-nodes
- vCluster access model: https://www.vcluster.com/docs/vcluster/manage/accessing-vcluster
