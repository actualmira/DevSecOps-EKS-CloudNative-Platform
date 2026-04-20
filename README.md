# Defense-in-Depth Cloud Security Architecture: Securing Cloud-Native Applications with Integrated Kubernetes, CI/CD, and AWS Controls
Defense-in-depth security for cloud-native applications on AWS EKS covering threat modelling, IaC scanning, Kubernetes hardening, container security, supply chain security, observability, and runtime threat detection.

---

## Table of Content

- [Project Overview](#-project-overview)
- [Threat Modelling](#-threat-modelling)
- [Phase 1: Local Foundation (Minikube)](#-phase-1-local-foundation-(minikube))
- [Phase 2: AWS Foundation](#-aws-foundation)
- [Phase 3: Security Pipeline and Supply Chain](#-phase-3-security-pipeline-and-supply-chain)
- [Phase 4: AWS Security Services](#-phase-4-aws-security-services)
- [Phase 5: Observability and Detection on AWS](#-phase-5-observability-and-detection-on-aws)
- [Phase 6: Testing and Validation](#-phase-6-testing-and-validation)

---

## Project Overview 
In this project, I will implement a defense-indepth security architecture for cloud-native applications across six phases; from threat modelling to local Kubernetes foundations through to production level deployment on AWS with automated threat detection and response. I will be using DVWA as the application and MariaDB as the database.

- **Threat Modelling**

This models the architecture, defines trust boundaries, Identifies threats applicable to the system, there impact, severity, and likelihood using STRIDE and DREAD framework, and determines the suitable mitigations which serves as the guide for my implementations **which is subject to change as I progress**.

- **Phase 1:Local Foundation (Minikube); In progress**

Implement and validate the neccessary security controls on minikube before provisioning any AWS resources. This covers baseline application deployment and connectivity testing, GPG signed commits and Pull Request enforcement on main branch, container security, Kubernetes security hardening, Network Policy and RBAC, OPA Gatekeeper policy enforcement with Rego, Falco runtime threat detection, Vault secrets management, observability stack, and Cosign image signing.

- **Phase 2: AWS Foundation**
  
- **Phase 3 — Security Pipeline and Supply Chain**
  
- **Phase 4 — AWS Security Services**
  
- **Phase 5 — Observability and Detection on AWS**
  
- **Phase 6 — Testing and Validation**

## Threat modelling

In order to fully understand the whole security architecture, I did threat modeling first, with that I could model every component including actors, data flows, processes, and data stores. This is important because it helps me understand what I’m building, what can go wrong, and how it can be mitigated which drives every architectural decision. This is a shift left security because it identifies and mitigates threats at design time rather than discovering them after deployment.

In this architecture I implemented a multi-environment deployment through Terraform workspaces. Due to cost constraints, the dev and production workspaces will not run silmutaneously. I will validate infrastructure changes in the dev workspace first, then promote to production using Terraform apply with a manual approval gate before destroying the dev workspace. This will ensure no untested or unreviewed infrastructure change reaches production directly. 

This threat model covers 47 threats across all six STRIDE categories applicable to this architecture. I applied DREAD scoring for risk quantification and NIST CSF mapping for compliance alignment. I did a risk analysis with mitigated risks, residual risks and accepted gaps documented.

### Threat Model Summary

| ID | Component | STRIDE | DREAD | Risk | Threat Summary | Key Controls |
|----|-----------|--------|-------|------|----------------|--------------|
| T4 | User HTTP Traffic | Tampering | 23 | CRITICAL | SQL injection and XSS payloads in HTTP requests | AWS WAF, PSA Restricted, OPA Gatekeeper |
| T1 | Internet User | Spoofing | 22 | CRITICAL | Authentication bypass using SQL injection or credential stuffing | AWS WAF rate limiting, TLS 1.3 |
| T23 | DVWA Pod | Elevation of Privilege | 17 | HIGH | Container escape through runtime vulnerability | PSA Restricted, Falco, Falco Sidekick |
| T9 | CI/CD Pipeline | Tampering | 18 | HIGH | Malicious workflow pushed directly to main branch | GPG signed commits, Checkov, Cosign |
| T30 | EKS API Server | Elevation of Privilege | 17 | HIGH | Service account exploits Kubernetes CVE to gain cluster-admin | RBAC, OPA Gatekeeper, GuardDuty |
| T45 | EC2 IMDS | Elevation of Privilege | 17 | HIGH | Container escape queries IMDS for node IAM credentials | IMDSv2, node least privilege, Falco |
| T14 | SSM Session Manager | Tampering | 17 | HIGH | Valid SSM access used to disable Falco or alter node state | IAM condition keys, keystroke logging, Falco |
| T7 | Pod-to-Pod Traffic | Tampering | 13 | MEDIUM | Compromised DVWA pod sends malicious queries to drop tables or escalate database privileges | NetworkPolicy default-deny, database privilege restriction, TLS 1.3 |
| T12 | Pod-to-AWS API (IRSA) | Information Disclosure | 15 | MEDIUM | IRSA token stolen from pod filesystem and used outside the cluster to access AWS resources | IRSA token expiry, VPC CIDR-scoped trust policy, CloudTrail, Falco |
| T37 | Vault | Information Disclosure | 17 | HIGH | Vault storage backend compromise reveals all stored secrets in plaintext | KMS auto-unseal, AES-256-GCM encryption, TLS 1.3, path-scoped policies |

*For a detailed insight on the complete threat model with DREAD scoring, risk matrix and risk posture summary, view in the Google Sheet below.*

[View Threat Model in Google Sheet](https://docs.google.com/spreadsheets/d/1aVw7FQazMh0S7U9Myd2VGUARhMJFIJVE/view?usp=sharing)

## Phase 1: Local Foundation (Minikube)

In this phase, I started with Minikube because I wanted to test and validate all security controls that are possible locally without the pressure of cloud costs. I installed the necessary tools on a Ubuntu 24.04 VirtualBox VM, created a GitHub repository, cloned it locally, and configured GPG signed commits with branch protection on main. This partly addresses the threat of an attacker with access to the repository through compromised GitHub credentials pushing a malicious workflow file directly to main by ensuring that every change to the repository requires a GPG-signed commit and a pull request, providing cryptographic proof of authorship and preventing direct pushes to main branch.

I then created Kubernetes manifests for DVWA and MariaDB, verified connectivity, and confirmed the application was working before adding any security controls. 

![Baseline Pod Connectivity](screenshots/phase1/baseline_pod_connection.png)

I deliberately deployed both pods in the same **"production"** namespace because they are web and database tiers of the same application; same team, same lifecycle, same deployment. I also mitigated the potential risk of co-locating them in subsequent stages by enforcing **RBAC** which gives each pod a **dedicated ServiceAccount** with empty roles so that neither pods can call the Kubernetes API or interact with the other's resources, and configured NetworkPolicy that enforces default-deny in the namespace with an explicit allow rule permitting **ONLY** DVWA to reach MariaDB on port 3306 an no other pod-to-pod traffic is permitted.

Here are the links to the complete manifest for both pods:

[DVWA Manifest](k8s/apps/dvwa.yaml)
[MariaDB Manifest](k8s/apps/mariadb.yaml)

### Kubernetes restricted profile standard on the production namespace

To mitigate the risk of a container runtime vulnerability such as a runc CVE or dirty-pipe class exploit that can allow an attacker to escape the container and access the underlying EKS worker node or an attacker with Kubernetes API access modifying a running pod specification to inject privileged capabilities, mount the host filesystem, or insert malicious code, I enforced the Kubernetes restricted profile standard on the production namespace. 

![k8s restricted label enforced](screenshots/phase1/k8s_restricted_label_enforced.png)

*Kubernetes restricted profile enforced with the running pods flagged*

I then edited the pods to meet up to the standard and reapplied.

```yaml
securityContext:
  runAsNonRoot: true
  fsGroup: 999
  fsGroupChangePolicy: "OnRootMismatch"
containers:
  - name: mariadb
    image: mariadb:10
    securityContext:
      allowPrivilegeEscalation: false
      runAsUser: 999
      readOnlyRootFilesystem: true
      seccompProfile:
        type: RuntimeDefault
      capabilities:
        drop:
          - ALL
```


- *allowPrivilegeEscalation: false* this will prevent my container process from gaining more privileges than it started with.
  
- *capabilities drop ALL* to drop all linux capabilities which are granular units of root privilege so that non of the containers can perform privileged operations even while running as a non-root user.
  
- *runAsNonRoot: true* to block the container from running as root because if a root process inside a container escapes the container boundary and lands on the host as root, it gives the attacker immediate control of the node.

- *seccompProfile: RuntimeDefault* to apply the container runtime's default seccomp filter, which blocks dangerous Linux system calls that the containers have no legitimate reason to invoke.
  
- It also blocks privileged containers, hostPath mounts, hostNetwork, and hostPID.

Any pod that does not meet these requirements is rejected at admission.

### I Implemented extra kubernetes security controls

On top of what the restricted profile mandates, I implemented the following controls for defense-indepth

- runAsUser: 999 on MariaDB and runAsUser: 998 on DVWA. This will prevent permission errors and avoid any ambiguity about which user the process identity should resolve to.

- fsGroup: 999 on MariaDB with fsGroupChangePolicy: OnRootMismatch. The MariaDB will require exclusive ownership of its data directory. Without correct ownership, MariaDB will refuse to start because it cannot read or write its own data files. I configured this to allow Kubernetes set the PersistentVolume group ownership before the container starts, avoiding the need for CHOWN capability, a privileged operation or an init script to fix permissions. *fsGroupChangePolicy: OnRootMismatch* ensures ownership is only changed if it does not already match to avoid unnecessary recursive permission operations on large volumes.

- readOnlyRootFilesystem: true on both pods. I mounted the container filesystem for both pods as read-only. This prevents a compromised container from writing malicious binaries, modifying application code, or staging exfiltrated data anywhere on its own filesystem outside of explicitly defined writable mounts. This directly reduces the blast radius if a compromise is successful, addressing the threats of an attacker escaping the container, or the database files being modified to inject backdoors or corrupt audit records.

- emptyDir volumes: The readOnlyRootFilesystem that I enabled required that I mount emptyDir volumes at every path the applications need to write to at runtime.

- Resource limits and requests on both pods: CPU and memory limits will prevent any single workload from exhausting the node resources, I also applied *[LimitRange](k8s/apps/limitrange.yaml)* on the production namespace as a safety net to enforce default resource requests and limits on any container that does not explicitly define them. These addresses the threat of a memory leak or deliberate resource bomb exhausting available node resources and causing pod evictions and service unavailability.

```yaml
    resources:
      requests:
        cpu: "200m"
        memory: "256Mi"
      limits:
        cpu: "400m"
        memory: "512Mi"
    volumeMounts:
      - name: dvwa-data
        mountPath: /tmp
      - name: apache-run
        mountPath: /var/run/apache2
      - name: dvwa-uploads
        mountPath: /var/www/html/hackable/uploads

volumes:
  - name: dvwa-data
    emptyDir: {}
  - name: apache-run
    emptyDir: {}
  - name: dvwa-uploads
    emptyDir: {}
```

- Liveness probes on both pods: I configured liveness probes to detect when a container is running but is no longer responding to requests. This will provide automated self healing for both pods. 

- On DVWA, I configured an HTTP probe to hit the application on port 80 every 30 seconds. For MariaDB, I configured an exec probe that runs mysqladmin ping using the dedicated healthcheck user every 30 seconds.
  
- I created the dedicated healthcheck user using an init script mounted at /docker-entrypoint-initdb.d/. I generated a strong password using openssl rand number generator, stored the password in Kubernetes Secret and injected it through environment variable which is consistent with the no hardcoded secret security principle.

- I created a dedicated healtchcheck user rather than reusing the application credentials because coupling health check credentials to the application credentials means if the application password rotates, the liveness probe will silently break leading to CrashLoopBack error on the pod making the database appear unavailable. Also, a dedicated user with minimal privileges follows the priciple of least privilege and will limit what an attacker can access if they observe the probe command.
  
- I also implemented password requirement for the dedicated healthcheck user to mitigate lateral movement. Although the user is restricted to localhost, all containers in a pod share the same network namespace and therefore the same localhost. If a sidecar were added to the MariaDB pod in future, it would inherit localhost trust. Without a password, any process in the pod could connect to MariaDB as the healthcheck user with no barrier.

```yaml
livenessProbe:
  exec:
    command:
      - /bin/sh
      - -c
      - mysqladmin ping -h 127.0.0.1 -uhealthcheck -p${HEALTHCHECK_PASSWORD}
  initialDelaySeconds: 60
  periodSeconds: 30
  timeoutSeconds: 10
  failureThreshold: 3
```

- I configured the liveness probe for mariadb to use -h 127.0.0.1 rather than -h localhost. This is because when -h localhost is used, MariaDB connects via Unix socket and applies unix_socket authentication based on the Linux system user identity. Since the healthcheck database user is not the system user, authentication fails regardless of password. Using -h 127.0.0.1 forces TCP which always uses password authentication. I used the IDENTIFIED VIA mysql_native_password clause in the init script to ensure password authentication is used regardless of MariaDB's defaults.

- However this alone was not sufficient because MariaDB's internal mysql_secure_installation equivalent runs after the init script and resets the authentication plugin for local users to unix_socket which overrides the plugin set during user creation. I fixed this by using a *Heredoc file* for the init script in order to control the sequence, then I added an explicit ALTER USER statement in the init script which runs after mysql_secure_installation completes.

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: mariadb-init
  namespace: production
data:
  healthcheck.sh: |
    #!/bin/sh
    mysql -u root -p"${MARIADB_ROOT_PASSWORD}" <<EOF
    CREATE USER IF NOT EXISTS 'healthcheck'@'127.0.0.1' IDENTIFIED BY '${HEALTHCHECK_PASSWORD}';
    ALTER USER 'healthcheck'@'127.0.0.1' IDENTIFIED VIA mysql_native_password USING PASSWORD('${HEALTHCHECK_PASSWORD}');
    REVOKE ALL PRIVILEGES ON dvwa.* FROM '${MARIADB_USER}'@'%';
    GRANT SELECT, INSERT, UPDATE ON dvwa.* TO '${MARIADB_USER}'@'%';
    DROP USER IF EXISTS 'root'@'%';
    FLUSH PRIVILEGES;
    EOF
```
![liveness probe succesful](screenshots/phase1/liveness_probe_succesful.png)
*MariaDB Liveness probe succesful with TCP Connection*

### Database privilege restriction 

By default MariaDB grants the application user full privileges on the database. I implemented an init script that revokes these and grants **ONLY** SELECT, INSERT, UPDATE permissions on the dvwa database user. This addresses the threat of a compromised DVWA pod sending malicious SQL queries attempting to drop tables, exfiltrate data, or escalate database privileges. I intentionally ommitted the DELETE permission because a compromised application pod with DELETE permission can delete users, wipe access logs, or destroy audit records. In production, DELETE operations such as log rotation would be handled by a dedicated maintenance database user triggered by a scheduled cron job, not available to the application at runtime. 

I restricted Root user to localhost only so that all database administration will require kubectl exec into the pod, which is logged on Kubernetes audit logs. This will prevent the risk of if port 3306 were ever accidentally exposed through a misconfigured NetworkPolicy or a cloud security group, an attacker cannot authenticate directly as root from outside the cluster.

### ConfigMap and manifest tampering
At this stage, anyone with kubectl write access to the production namespace can apply any manifest including creating or modifying ConfigMaps. The current control is Git branch protection with GPG-signed commits, Pod ServiceAccounts having zero API permissions. I intend to close the gap as well by applying Cosign and OPA Gatekeeper signature validation alongside IAM-scoped kubectl access.

### StatefulSet for MariaDB and Deployment for DVWA

I configured MariaDB as StatefulSet because it is a database that requires a PersistentVolume for the database files, the pod needs a stable and predictable identity so that the volume claim can always reattach to the correct pod on restart. A StatefulSet provides this stable identity and manages the PersistentVolumeClaim lifecycle. 
In contrast, I configured the DVWA pod as a Deployment because it is stateless and each replica is interchangeable, it can be replaced or rescheduled without the risk of a pod restarting with no guarantee of reattaching to the same volume, leaving data inaccessible.

### StorageClass volumeBindingMode: Immediate

I configured the StorageClass for MariaDB to use volumeBindingMode: Immediate instead of WaitForFirstConsumer because on Minikube's single-node setup, WaitForFirstConsumer creates a deadlock, the scheduler waits for a node placement decision before creating the volume, but the pod cannot be scheduled without the volume ready. Immediate provisions the volume as soon as the PVC is created. This will be changed to WaitForFirstConsumer on EKS so that the volume is created in the same availability zone as the scheduled pod, preventing zone mismatch failures.

### RBAC: Dedicated ServiceAccount per workload

I created dedicated [ServiceAccount](k8s/apps/rbac.yaml) per workload for dvwa and MariaDB with empty Roles granting zero Kubernetes API permissions because neither pod needs to call the Kubernetes API. The dedicated identity ensures that audit logs are recorded separately for each ServiceAccount, and permissions can be adjusted per workload independently without affecting the other. This directly addresses the threat of a stolen Kubernetes service account token being used to impersonate an administrator and perform unauthorised cluster operations, or a service account with limited permissions exploiting a Kubernetes vulnerability to escalate to cluster-admin. Because ServiceAccounts are mounted at the pod level, not the container level, every container in a pod inherits the same ServiceAccount token. If a pod had multiple containers with different trust levels, the less trusted container would inherit the same token as the more privileged one. 

### NetworkPolicy with Calico CNI

I applied three [NetworkPolicy objects](k8s/apps/network_policy.yaml): 

- A default-deny policy that blocks all ingress and egress across the namespace

- A dvwa-np policy allowing ingress on port 80 from 0.0.0/0. DVWA is the web application and it needs to accept HTTP requests from users. In Minikube this is direct access via NodePort. On AWS, I will replace this with ingress only from the Application Load Balancer Security Group, removing direct internet access to the pod entirely and routing all traffic through WAF inspection first. I also allowed an egress to MariaDB **ONLY** on port 3306 and, egress to DNS on port 53 because without DNS egress, name resolution will fail and DVWA cannot locate the database regardless of whether the connection itself would be permitted.

- mariadb-np to allow ingress from DVWA **ONLY** on port 3306 and **ONLY** from pods labelled app=dvwa.

The network policies by isolating the database traffic to only dvwa, addresses the threat of an unencrypted database connection revealing passwords or query content to a malicious pod on the same node. By denying all egress except for DNS and MariaDB, the network policy with the RBAC configuration of minimal role service accounts, address the threat of a stolen service account token being used to call the Kubernetes API server from inside a pod.

Minikube's default CNI does not enforce NetworkPolicy so I restarted minikube with Calico to enable enforcement. I Verified before and after: without Calico, MariaDB could reach DVWA. With Calico, the same connection is blocked, proving the policies are enforced.

![After Calico](screenshots/phase1/network_policy-enforced.png)
*Network policy enforced*



### NetworkPolicy label spoofing
The Network Policies select pods by label, this means that any pod created in the production namespace with a matching label will inherit the same network access rules including egress to MariaDB on port 3306. The current control is RBAC for both pod ServiceAccounts have zero API permissions, so an attacker cannot create malicious pods from a compromised container through the Kubernetes API using its own token but someone with kubectl access can. This is a gap at this stage which I will mitigate in future stages with Cosign image signing and OPA Gatekeeper admission constraint that will validate the signatures and enforce blocking of any pod with an unsigned image regardless of what labels it carries.


### OPA Gatekeeper Policy with Rego

I installed OPA Gatekeeper wrote custom ConstraintTemplates using Rego for the kubernetes security controls I enforced, this serves as a second layer of control acting at the admission level. I configured all ConstraintTemplates to target both naked Pods and controller resources so that every resource is intercepted irrespective of how it is applied. 

- **[EnforceNonRootUser](k8s/opa_gatekeeper/01-templates/enforce_non_root.yaml)** [See

```yaml
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package enforcenonrootuser
        violation[{"msg": msg}] {
          pod_spec := get_pod_spec(input.review.object)
          container := pod_spec.containers[_]
          not container.securityContext.runAsNonRoot == true
          not pod_spec.securityContext.runAsNonRoot == true
          msg := sprintf("RunAsNonRoot is not enforced for container '%v'", [container.name])
        }

        violation[{"msg": msg}] {
          pod_spec := get_pod_spec(input.review.object)
          container := pod_spec.containers[_]
          container.securityContext.runAsNonRoot == false
          msg := sprintf("RunAsNonRoot is overridden for container '%v'", [container.name])
        }

        violation[{"msg": msg}] {
          pod_spec := get_pod_spec(input.review.object)
          container := pod_spec.containers[_]
          container.securityContext.runAsUser == 0
          msg := sprintf("Container '%v' must not run as user 0", [container.name])
        }

        violation[{"msg": msg}] {
          pod_spec := get_pod_spec(input.review.object)
          pod_spec.securityContext.runAsUser == 0
          msg := "Run as user 0 is prohibited"
        }

        get_pod_spec(obj) = spec {
          obj.kind == "Pod"
          spec := obj.spec
        }

        get_pod_spec(obj) = spec {
          spec := obj.spec.template.spec
        }
```
 **[See Constraint](k8s/opa_gatekeeper/02-constraints/runasnonroot_constraint.yaml)**

- **[RequireResourceLimits](k8s/opa_gatekeeper/01-templates/require_resource_limits.yaml)**: **[See Constraint](k8s/opa_gatekeeper/02-constraints/require_resource_limits_constraint.yaml)**

- **[DenyPrivilegedContainer](k8s/opa_gatekeeper/01-templates/deny_privileged_containers.yaml)**; **[See Constraint](k8s/opa_gatekeeper/02-constraints/deny_privileged_containers_constraint.yaml)**

- **[EnforceReadOnlyRootFilesystem](k8s/opa_gatekeeper/01-templates/read_only_root_fs.yaml)** **[See Constraint](k8s/opa_gatekeeper/02-constraints/readonly_root_fs_constraint.yaml)**

- **[BlockLatestImageTag](k8s/opa_gatekeeper/01-templates/block_latest_image.yaml)**: I scoped this to production namespace only so as to prevent applications from automatically pulling a new image on pod restart which could introduce untested changes without a deployment pipeline. However a developer may need to legitimately use kubectl run without specifying a tag for quick testing. By scoping this constraint to production namespace, it preserves workflow flexibility outside production while enforcing stability where it matters. **[See Constraint](k8s/opa_gatekeeper/02-constraints/block_latest_image_constraint.yaml)**

- **[EnforceRBACServiceAccount](k8s/opa_gatekeeper/01-templates/enforce_rbac_service_account.yaml)**: I configured four violation blocks that targets Pods, Roles, ClusterRoles, RoleBindings and ClusterRoleBindings. Blocks 1 and 2 ensure that every resource has a dedicated ServiceAccount that is not the default service account, addressing the threat of a compromised pod inheriting excessive API permissions through the default account (even if someone grants an excessive permission to the default account). Block 3 blocks RoleBindings/ClusterRoleBindings that grant cluster-admin, admin or edit roles which are dangerous built-in roles that grant broader permissions than any application workload will require. Block 4 blocks wildcard permissions on Role/ClusterRole verbs, resources and apiGroups because a wildcard on any single dimension can grant excessive permissions regardless of what the others restrict.

```yaml
targets:
  - target: admission.k8s.gatekeeper.sh
    rego: |
      package enforcerbacserviceaccount
      violation[{"msg": msg}] {
        pod_spec := get_pod_spec(input.review.object)
        pod := object.get(input.review.object.metadata, "name", input.review.object.metadata.generateName)
        not pod_spec.serviceAccountName
        msg := sprintf("Service account is not configured for pod '%v'", [pod])
      }

      violation[{"msg": msg}] {
        pod_spec := get_pod_spec(input.review.object)
        pod := object.get(input.review.object.metadata, "name", input.review.object.metadata.generateName)
        pod_spec.serviceAccountName == "default"
        msg := sprintf("Default service account is not allowed for pod '%v'", [pod])
      }

      violation[{"msg": msg}] {
        kinds := {"RoleBinding", "ClusterRoleBinding"}
        kinds[input.review.kind.kind]
        forbidden_roles := {"cluster-admin", "admin", "edit"}
        role_name := input.review.object.roleRef.name
        forbidden_roles[role_name]
        msg := sprintf("Assigning the built in role '%v' is prohibited", [role_name])
      }

      violation[{"msg": msg}] {
        kinds := {"Role", "ClusterRole"}
        kinds[input.review.kind.kind]
        rule := input.review.object.rules[_]
        wildcard(rule)
        msg := sprintf("Role '%v' is not allowed to use Wildcard '*' permissions", [input.review.object.metadata.name])
        }

```
  **[See Constraint](k8s/opa_gatekeeper/02-constraints/rbac_service_account_constraint.yaml)**

- **[EnforceNetworkPolicy](k8s/opa_gatekeeper/01-templates/enforce_network_policy.yaml)**: 

I used nested object.get calls rather than direct path access because direct path access will return undefined for namespaces with no networking resources defined which will cause the Rego rule to fail silently. Block 1 checks that at least one NetworkPolicy exists in the namespace. Block 2 checks that at least one existing NetworkPolicy selector covers the specific pod labels being deployed.

```yaml
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package enforcenetworkpolicy
        violation[{"msg": msg}] {
          ns := input.review.object.metadata.namespace
          policies := object.get(object.get(data.inventory.namespace, ns, {}), "networking.k8s.io/v1", {})
          networkpolicies := object.get(policies, "NetworkPolicy", {})
          count(networkpolicies) == 0
          msg := sprintf("Namespace '%v' does not have a network policy ", [ns])
        }

        violation[{"msg": msg}] {
          ns := input.review.object.metadata.namespace
          pod_label := get_pod_label(input.review.object)
          policies := data.inventory.namespace[ns]["networking.k8s.io/v1"]["NetworkPolicy"]
          pod_policies := [p |
            p := policies[_]
            match_policies(pod_label, p.spec.podSelector)
            ]
          count(pod_policies) == 0
          msg := sprintf("The pod '%v' must have a network policy assigned", [object.get(input.review.object.metadata, "name", input.review.object.metadata.generateName)])
        }

        get_pod_label(obj) = label {
          obj.kind == "Pod"
          label := obj.metadata.labels
        }

        get_pod_label(obj) = label {
          label := obj.spec.template.metadata.labels
        }

        match_policies(labels, selector) {
          object.get(selector, "matchLabels", {}) == {}
        }

        match_policies(labels, selector) {
          ml := object.get(selector, "matchLabels", {})
          count(ml) > 0
          count({key | labels[key] == ml[key]}) == count(ml)
        }
```
  **[See Constraint](k8s/opa_gatekeeper/02-constraints/network_policy_constraint.yaml)**

To enforce the network policy, I configured the [config file](k8s/opa_gatekeeper/00-setup/sync.yaml) for OPA Gatekeeper to enable it sync information from *data.inventory* because without it, Gatekeeper as an admission controller can only inspect the resource currently being submitted.

```yaml
apiVersion: config.gatekeeper.sh/v1alpha1
kind: Config
metadata:
  name: config
  namespace: "gatekeeper-system"
spec:
  sync:
    syncOnly:
      - group: "networking.k8s.io"
        version: "v1"
        kind: "NetworkPolicy"
```

### I validated all these rules by applying a non complaint pod

![opa gatekeeper violation](screenshots/phase1/opa_gatekeeper_violation.png)
