# Technical

## Core Technology Stack

The experimentation environment centers around vCluster and Kubernetes-based virtual cluster architectures.

The implementation should support experimentation using local Kubernetes environments.

The environment should remain lightweight and locally reproducible.

---

# No Dev Container Usage

This repository intentionally avoids dev container workflows.

The focus is exclusively on:

- Kubernetes experimentation
- vCluster architecture exploration
- Virtual cluster operational models

The implementation should not depend on dev container abstractions.

---

# Experiment 1: Shared Infrastructure Host Cluster

The first architecture model includes:

- A base Kubernetes host cluster
- Shared infrastructure components installed directly into the host cluster
- Application-oriented virtual clusters layered on top

Shared infrastructure may include:

- Operators
- Foundational services
- Platform tooling
- Shared management systems

Application vClusters should contain primarily application-specific workloads and resources.

---

# Experiment 2: Infrastructure-Isolated vCluster Model

The second architecture model inverts the infrastructure placement strategy.

In this model:

- Foundational infrastructure components live inside dedicated infrastructure-oriented virtual clusters
- The host cluster remains minimal
- Application-oriented vClusters contain only application-specific resources
- Infrastructure isolation occurs through virtual cluster boundaries

The implementation should evaluate operational viability of infrastructure isolation through vClusters themselves.

---

# Experiment 3: Dual-Cluster Architecture

The third experiment introduces multiple physical Kubernetes clusters.

The intended model includes:

- One Kubernetes cluster hosting application-oriented vClusters
- Another Kubernetes cluster hosting infrastructure-oriented vClusters and management systems

The implementation should support experimentation with cross-cluster coordination and operational separation.

---

# Cross-Cluster Communication Exploration

The implementation should explore multiple communication and administration models.

Areas of exploration include:

- Infrastructure cluster → individual vCluster communication
- Infrastructure cluster → host cluster communication
- Direct vCluster management
- Host-mediated management
- Cross-cluster administrative coordination

The architecture should remain flexible enough to test multiple operational boundaries.

---

# Isolation and Boundary Exploration

The experiments should evaluate:

- Infrastructure isolation boundaries
- Application isolation boundaries
- Shared operator placement
- Resource ownership models
- Administrative separation concerns

The implementation should support comparing differing responsibility distributions.

---

# Operational Experimentation Goals

The environment should support iterative experimentation for:

- Cluster topology design
- Infrastructure placement strategies
- Management plane organization
- Cross-cluster orchestration
- Multi-tenant isolation concepts
- Shared services placement

The repository should prioritize fast iteration and comparative architectural analysis.

---

# Local Reproducibility

The implementation should remain locally reproducible.

Requirements include:

- Local Kubernetes support
- Lightweight setup flows
- Disposable experimentation environments
- Easy environment reset/rebuild capability

The environment should optimize for experimentation speed rather than production durability.

---

# Extensibility Requirements

The architecture should remain extensible for future experimentation involving:

- Additional virtual cluster topologies
- Additional management models
- Federation-style architectures
- Shared services architectures
- Multi-environment orchestration
- Additional Kubernetes distributions

The repository should function as a flexible experimentation platform rather than a narrowly scoped implementation.