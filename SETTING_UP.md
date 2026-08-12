# Setting Up Distributed OneUptime Monitoring on Kubernetes

For the project architecture, implemented reliability controls, and operational
documentation, see the [project README](README.md).

A hands-on implementation of a two-node Kubernetes cluster running OneUptime, configured so that the core system and its default probe live on Node 1, an external probe lives on Node 2, and each node cross-monitors the other over the network.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Phase 1 — Provisioning the Cluster](#phase-1--provisioning-the-cluster)
3. [Phase 2 — Node Labeling](#phase-2--node-labeling)
4. [Phase 3 — Installing the OneUptime Core System (Node 1)](#phase-3--installing-the-oneuptime-core-system-node-1)
5. [Phase 4 — Deploying the Second Probe (Node 2)](#phase-4--deploying-the-second-probe-node-2)
6. [Phase 5 — Cross-Monitoring Configuration](#phase-5--cross-monitoring-configuration)
7. [Project Summary](#project-summary)
8. [Deliverables Checklist](#deliverables-checklist)
9. [Troubleshooting Log](#troubleshooting-log)

---

## 1. Prerequisites

Confirm the following tools are installed locally before starting:

```bash
docker --version
minikube version
kubectl version --client
helm version
```

---

## Phase 1 — Provisioning the Cluster

### 1.1 Clean up any previous cluster (if applicable)

```bash
minikube delete -p oneuptime
```

> This removes only this project's Minikube profile. It does not delete other
> local Minikube clusters.

### 1.2 Start a two-node cluster with sufficient resources

```bash
minikube start -p oneuptime --nodes 2 --memory=8192 --cpus=4
kubectl config use-context oneuptime
```

> The `--memory` and `--cpus` flags are set explicitly to avoid resource-starvation symptoms such as `TLS handshake timeout` on the API server, which can occur on default (lightweight) minikube profiles.

### 1.3 Verify

```bash
kubectl get nodes
```

Both nodes should report `Ready`:

```
NAME            STATUS   ROLES           AGE   VERSION
oneuptime       Ready    control-plane   ...   v1.35.1
oneuptime-m02   Ready    <none>          ...   v1.35.1
```

> With the `oneuptime` profile, this guide assumes the node names are
> `oneuptime` and `oneuptime-m02`. Verify them with `kubectl get nodes` and
> substitute the actual names if your Minikube version produces different ones.

---

## Phase 2 — Node Labeling

### 2.1 Label each node by role

```bash
kubectl label nodes oneuptime app=oneuptime-core
kubectl label nodes oneuptime-m02 app=oneuptime-probe
```

### 2.2 Verify

```bash
kubectl get nodes --show-labels
```

Confirm each node carries the correct label in the `LABELS` column. **This output is one of the required deliverables.**

---

## Phase 3 — Installing the OneUptime Core System (Node 1)

### 3.1 Add the Helm repository

```bash
helm repo add oneuptime https://helm-chart.oneuptime.com/
helm repo update
```

### 3.2 Create the namespace

```bash
kubectl create namespace oneuptime
```

### 3.3 Inspect the chart's default values (optional, but recommended)

```bash
helm show values oneuptime/oneuptime > default-values.yaml
grep -n "nodeSelector" default-values.yaml
```

Run this after every `helm repo update`; the checked-in/generated copy can lag
behind the published chart. This reveals the exact structure each
`nodeSelector` field expects (for example `postgresql.primary.nodeSelector` and
`redis.master.nodeSelector`) and newly introduced blocks such as `runner`.

### 3.4 Build `values.yaml`

`values.yaml` is the first-stage installation file. It starts the core,
ClickHouse, KEDA, the in-cluster Runner, and the internal probe on Node 1.
`probe2-values.yaml` is applied later as an overlay. `all.yaml` is maintained as
the final merged snapshot of those two files; until a fresh Probe Two key is
inserted, its key field deliberately contains a placeholder.

```bash
cat > values.yaml << 'EOF'
host: "localhost:8080"
httpProtocol: http

image:
  pullPolicy: IfNotPresent

clickhouse:
  enabled: true
  nodeSelector:
    app: oneuptime-core

keda:
  enabled: true
  nodeSelector:
    app: oneuptime-core

nginx:
  nodeSelector:
    app: oneuptime-core

postgresql:
  primary:
    nodeSelector:
      app: oneuptime-core

redis:
  master:
    nodeSelector:
      app: oneuptime-core

app:
  nodeSelector:
    app: oneuptime-core

worker:
  nodeSelector:
    app: oneuptime-core

migrate:
  nodeSelector:
    app: oneuptime-core

# In chart 12.x this is the in-cluster AI code-fix component. It auto-registers.
runner:
  enabled: true
  nodeSelector:
    app: oneuptime-core

deployment:
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 0
      maxUnavailable: "100%"

probes:
  one:
    nodeSelector:
      app: oneuptime-core
EOF
```

In chart `12.x`, the in-cluster AI code-fix component is configured under
`runner`; there is no separate top-level `aiAgent` value. The Runner is enabled,
pinned to Node 1, and auto-registers without a dashboard ID/key.

### 3.5 Install the chart

```bash
helm install oneuptime oneuptime/oneuptime -n oneuptime -f values.yaml
```

Expected output: `STATUS: deployed`

### 3.6 Confirm pods are running

```bash
kubectl get pods -n oneuptime -w
```

> Pod startup can take a few minutes depending on your internet connection (large images need to be pulled). This is a good moment for a coffee break.

```bash
kubectl get pods -n oneuptime -o wide
```

Confirm every core pod and `oneuptime-probe-one` has `oneuptime` (Node 1) in
the `NODE` column. **This output is one of the required deliverables.**

---

## Phase 4 — Deploying the Second Probe (Node 2)

### 4.1 Access the dashboard via port-forward

Verify the service:

```bash
kubectl get svc -n oneuptime oneuptime-nginx
```

In a **separate terminal tab** (this one will stay open, running in the foreground):

```bash
kubectl port-forward svc/oneuptime-nginx 8080:80 -n oneuptime
```

Open in your browser:

```
http://localhost:8080
```

To register directly, navigate to:

```
http://localhost:8080/accounts/register
```

### 4.2 Create an account / sign in

Register a new account from the sign-up screen and log in.

> `host: "localhost:8080"` and `httpProtocol: http` in `values.yaml` are what prevent a `Network Error` during registration — if you see one, double-check these two fields.

### 4.3 Retrieve the Probe Key

- Navigate to **Project → Products → Monitor → Probes** (the "Probes" tab sits at the bottom of the Monitor sidebar)
- Click **"Add Probe"**
- Name it `External-Probe-Node2`
- Create it, then copy the generated **Probe Key** from the dashboard

![Create External-Probe-Node2 and copy its Probe Key](img/create_new_probe.png)

*The newly created `External-Probe-Node2` initially appears as `Disconnected`. This is expected because its Kubernetes pod has not been deployed yet. Copy the Probe Key shown by the dashboard; the Helm upgrade below uses that key to register and connect the pod.*

> Any key from the deleted cluster is stale. Both `probe2-values.yaml` and
> `all.yaml` initially contain a placeholder; use only the newly generated key
> from this fresh dashboard.

### 4.4 Create `probe2-values.yaml`

Using the real key retrieved from the dashboard:

```bash
cat > probe2-values.yaml << 'EOF'
probes:
  two:
    name: "External-Probe-Node2"
    description: "Probe 2 on Node 2"
    enabled: true
    monitoringWorkers: 3
    monitorFetchLimit: 10
    key: "REPLACE_WITH_THE_NEW_PROBE_KEY"
    replicaCount: 1
    ports:
      http: 3874
    nodeSelector:
      app: oneuptime-probe
EOF
```

Replace `REPLACE_WITH_THE_NEW_PROBE_KEY` with the exact key copied in Step 4.3.
Do not reuse the old key from `all.yaml`, and do not commit the new key to Git.

### 4.5 Upgrade the release to add the second probe

```bash
helm upgrade oneuptime oneuptime/oneuptime -n oneuptime -f values.yaml -f probe2-values.yaml
```

> Both values files must be supplied together. `values.yaml` preserves the core
> services and Node 1 placement; `probe2-values.yaml` adds only Probe Two.

Wait for `oneuptime-probe-two` to start. The dashboard entry that initially
showed `Disconnected` should change to `Connected`/`Online` after the pod starts
with the matching Probe Key.

### 4.6 Restart the dashboard port-forward after the upgrade

The Helm upgrade can recreate application or Nginx pods, which may close the
previous port-forward session. In a separate terminal tab, start it again:

```bash
kubectl port-forward svc/oneuptime-nginx 8080:80 -n oneuptime
```

Then reopen or refresh:

```text
http://localhost:8080
```

Keep the port-forward terminal running. If the command reports that port `8080`
is already in use, the previous port-forward is still active; keep using that
session instead of starting a second one.

### 4.7 Keep `all.yaml` synchronized

After replacing the placeholder in `probe2-values.yaml`, put the same fresh key
in `all.yaml`. The three files follow this invariant:

```text
all.yaml = values.yaml + probe2-values.yaml
```

The normal deployment remains the two-stage Helm flow above. `all.yaml` is the
single-file snapshot of the final working state and must not contain an old
cluster's Probe Two key.

### 4.8 Verify placement

```bash
kubectl get pods -n oneuptime -o wide
```

Confirm the new `oneuptime-probe-two-...` pod's `NODE` column reads
`oneuptime-m02` (Node 2).

**Actual result:**

```
NAME                                    READY   STATUS    RESTARTS   AGE   NODE
oneuptime-probe-one-77f6b787b7-gx9r8    1/1     Running   0          47s   oneuptime
oneuptime-probe-two-57c685c7ff-wqmhf    1/1     Running   0          71s   oneuptime-m02
```

✅ `probe-one` → Node 1, `probe-two` → Node 2. This satisfies the Phase 4 placement requirement.

---

## Phase 5 — Cross-Monitoring Configuration

### 5.1 Confirm both probes report Online

Dashboard → **Probes** page:

- `Probe` (Node 1, default) → **Connected/Online** ✅
- `External-Probe-Node2` (Node 2) → **Connected/Online** ✅

The screenshot below (taken from a monitor's **Probes** tab) confirms both probes are registered and connected:

![Both probes connected](img/monitor-probes-connected.png)
*Both the default probe (Node 1) and External-Probe-Node2 (Node 2) report "Connected".*

### 5.2 Create a lightweight target on Node 2

OneUptime itself is installed and managed by the Helm release. `nginx-target`,
however, is not part of the OneUptime chart or either values file; it is a
separate test workload created manually with `kubectl` so the Node 1 probe has a
simple HTTP target on Node 2. If the Minikube profile is deleted, create this pod
and service again after reinstalling OneUptime.

```bash
kubectl run nginx-target --image=nginx --overrides='{"spec": {"nodeSelector": {"app": "oneuptime-probe"}}}' -n oneuptime
kubectl expose pod nginx-target --port=80 --name=nginx-target-svc -n oneuptime
```

**Verify:**

```bash
kubectl get pods -n oneuptime -o wide | grep nginx-target
kubectl get svc -n oneuptime nginx-target-svc
```

Confirm `nginx-target`'s `NODE` column reads `oneuptime-m02` (Node 2).

### 5.3 Create Monitor 1: Node 1's probe → watches Node 2

Dashboard → **Monitors → Create Monitor**:

| Field | Value |
|---|---|
| Monitor Type | Website |
| Monitor Name | `Node2-Nginx-Health-Check` |
| URL | `http://nginx-target-svc.oneuptime.svc.cluster.local` |
| Probe | **Probe** (Node 1, default) |

✅ This monitor lets **Node 1's probe check Node 2's reachability** over the network.

Once the check runs, the monitor's summary confirms the probe used and a successful response:

![Node 2 monitor summary](img/monitor-node2-nginx-summary.png)
*`Node2-Nginx-Health-Check` — served by "Probe" (Node 1), HTTP 200 in 3 ms against `nginx-target-svc`.*

### 5.4 Create Monitor 2: Node 2's probe → watches Node 1

Dashboard → **Monitors → Create Monitor**:

| Field | Value |
|---|---|
| Monitor Type | Website |
| Monitor Name | `Node1-App-Health-Check` |
| URL | `http://oneuptime-app.oneuptime.svc.cluster.local:3002/status/live` |
| Probe | **External-Probe-Node2** |

✅ This monitor lets **Node 2's probe check the core system's health** on Node 1.

> `/status/live` is the same health-check path already used internally by the chart's `startupProbe`/`livenessProbe` definitions (confirmed during earlier OOM/probe log analysis), making it the correct endpoint for verifying the core system's health.

The monitor summary below confirms it is served by `External-Probe-Node2` and receiving a healthy response from Node 1:

![Node 1 monitor summary](img/monitor-node1-app-summary.png)
*`Node1-App-Health-Check` — served by "External-Probe-Node2" (Node 2), HTTP 200 in 8 ms against the core app's `/status/live` endpoint.*

### 5.5 Final verification

Both monitors were opened individually and confirmed:

- **Status**: `Operational` / `Online`
- **Monitor Events / Evaluation Logs** show successful, passing checks

✅ The cross-monitoring topology is complete: Node 1 and Node 2 monitor each other bidirectionally, exactly as required.

---

## Project Summary

| Requirement | Status |
|---|---|
| Two-node Kubernetes cluster (minikube) | ✅ Done |
| Node labeling (`oneuptime-core` / `oneuptime-probe`) | ✅ Done |
| Core system + default probe → Node 1 | ✅ Done |
| Second (external) probe → Node 2 | ✅ Done |
| Both probes report Online | ✅ Done |
| Cross-monitoring (Node 1 ↔ Node 2) | ✅ Done |

---

## Deliverables Checklist

1. **Terminal output:**
   - `kubectl get nodes --show-labels`
   - `kubectl get pods -n oneuptime -o wide`
2. **Dashboard screenshots:**
   - Both probes listed as "Online" (Probes page) — see [5.1](#51-confirm-both-probes-report-online)
   - `Node2-Nginx-Health-Check` and `Node1-App-Health-Check` monitor detail/summary pages — see [5.3](#53-create-monitor-1-node-1s-probe--watches-node-2) and [5.4](#54-create-monitor-2-node-2s-probe--watches-node-1)
3. **Issues encountered and resolutions** — see below

---

## Troubleshooting Log

| Issue | Root Cause | Resolution |
|---|---|---|
| `Request failed to http://localhost/identity/signup. Network Error` | Chart's `host` value was portless (`localhost`) while the app was accessed on `:8080` | Added `host: "localhost:8080"` and `httpProtocol: http` to `values.yaml` |
| Namespace/pods refuse to delete cleanly / cluster becomes unusable | Accumulated crash loops and resource exhaustion | Reset only this project via `minikube delete -p oneuptime`, then recreate the named profile with adequate resources |
| `oneuptime-migrate` job `OOMKilled` | The chart hard-codes `NODE_OPTIONS=--max-old-space-size=8096` (an 8 GB heap ceiling); this value cannot be overridden through `values.yaml` (no `env` field is exposed for this job), and total node memory was insufficient | Increased Docker Desktop's memory allocation and started nodes with `--memory=8192`; the migration job completed successfully after a few automatic retries (`backoffLimit: 6`) |
| `app` / `nginx` pods `OOMKilled` during rolling updates | During a rolling update, the old and new pod briefly coexist, temporarily doubling memory demand | Pods self-healed automatically (restart count increased); the durable fix is provisioning enough node memory headroom, and/or switching `deployment.updateStrategy` to a Recreate-equivalent (`maxSurge: 0`, `maxUnavailable: "100%"`) to avoid the overlap entirely |
| Second probe stays `Disconnected` or unauthorized after a full reset | The key in the old `all.yaml` belongs to the deleted database and is no longer valid | Bring up the base installation first, create `External-Probe-Node2` in the fresh dashboard, copy its new key into `probe2-values.yaml`, then run the Phase 4 Helm upgrade |
| Re-adding a probe under the same name after a pod-level failure returns a database conflict (`already exists`) | The PostgreSQL PVC survives pod crashes and Helm upgrades, so the old Probe row can remain even when its pod is gone. A profile reset behaves differently and deletes the database entirely. | If the cluster was not reset, reuse the key of the existing dashboard probe or remove the stale row before creating another probe with the same name. After `minikube delete -p oneuptime`, create a new account, probes, and monitors because the old database no longer exists. |

> **Note:** `minikube delete -p oneuptime` removes only the `oneuptime`
> profile. Other Minikube profiles and local files such as `values.yaml` remain
> untouched. A new Probe Two key is still required because this profile's
> PostgreSQL data is deleted with the cluster.

> **General lesson learned:** This chart's schema validation (`values.schema.json`) is strict — fields like `env`/`NODE_OPTIONS` are not exposed for override on any service; only standard Kubernetes fields such as `resources`, `nodeSelector`, `tolerations`, and `affinity` can be customized. As a result, the most reliable way to resolve memory-related failures was to increase the node's total physical resources rather than attempting to tune in-container settings that the chart does not expose.
