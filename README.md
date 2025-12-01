# kind-vcluster-experimentations

> [!WARNING]
> **AI-authored:** This change was autonomously planned and implemented by an AI software factory from a human-authored specification, with possible subsequent human review or modification.

Compares two vCluster topologies on a single-node kind host: shared-host (infra Deployment on host cluster) and isolated (infra Deployment inside a dedicated infra vCluster). Both use identical versions, manifests, and probes.

```sh
helm repo add loft-sh https://charts.loft.sh

bash scripts/up-host.sh
bash scripts/observe.sh host
bash scripts/down.sh

bash scripts/up-isolated.sh
bash scripts/observe.sh isolated
bash scripts/down.sh
```

## Notes

- no longer believe in this strategy
- original idea; explore virtual clusters across different configurations/options
- not pleased with the resulting structure/design
- feels laborious
- not convinced by the vCluster model overall
- seems to reinvent a lot of existing machinery
- added structure does not appear to materially improve effectiveness of running services
- likely abandon this direction
