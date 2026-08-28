# Defense-in-Depth Cloud Security Architecture: Securing Cloud-Native Applications with Integrated Kubernetes, CI/CD, and AWS Controls
Defense-in-depth security for cloud-native applications on AWS EKS covering threat modelling, IaC scanning, Kubernetes hardening, container security, supply chain security, observability, and runtime threat detection.

---

## Project Overview 

- I implemented a defence-in-depth security architecture for cloud native applications across phases; from threat modelling to runtime detection and supply chain security, using DVWA as the intentionally vulnerable application and MariaDB as the database to validate controls against realistic attack surfaces.

- I implemented Kubernetes security controls including Cilium network policies for least privilege network connectivity. RBAC to limit what each service account can do within the cluster, preventing lateral movement. Pod Security Standards at the namespace level to block privileged containers and missing security contexts at admission. OPA Gatekeeper with Rego at the cluster level to catch misconfigurations.

- I implemented secrets management with HashiCorp Vault and ESO, eliminating hardcoded credentials from manifests and application code. I deployed cert manager and trust-manager to secure communication between Vault and ESO over TLS, with trust manager distributing only the public CA certificate to the ESO namespace.

- I deployed Falco to detect security runtime threats, and forward structured alerts through Falcosidekick to Loki for real-time correlation in Grafana.

- I configured AWS security controls including IRSA for workload identity, KMS for encryption at rest, security groups for micro segmentation, WAF and ALB for ingress and its protection, GuardDuty for account-wide threat detection, CloudTrail for API audit, and AWS Config for continuous compliance monitoring with automated remediation of misconfigurations through EventBridge and Lambda.

- I configured separate IAM roles for each node group for least privilege permissions and to contain blast radius. I enforced IMDSv2 on all nodes to prevent SSRF-based credential theft. I enabled KMS encryption for etcd secrets at rest.

- I configured SSM Session Manager as the only administrative access path to nodes, logging all session activity to an Object-Locked S3 bucket and CloudWatch for real-time monitoring. I configured SSM Patch Manager with a scan-only baseline on a weekly maintenance window, routing scan output to S3 for compliance evidence.

- I built the observability stack with Prometheus, Loki, and Grafana which provides a single pane of glass to correlate infrastructure metrics, application logs, and Falco runtime alerts.

- I separated Terraform root modules into independent stacks and managed it with Terragrunt for dependency-aware planning and reducing blast radius. I implemented GitHub OIDC federation with separate least-privilege plan and apply roles scoped to each workflow file and branch to prevent cross-workflow privilege escalation.

- I am currently implementing the remaining supply chain controls including SBOM generation, image signing with Cosign, GitHub Actions workflow files with SHA pinning for all third-party actions, secrets and security scanning with TruffleHog, Trivy, Snyk, Hadolint, and Checkov, and GitOps with ArgoCD.

- I am also completing the automated patching loop by adding an EventBridge rule to detect non-compliant scan findings, trigger a CI/CD pipeline webhook that will update the Terraform launch template with the latest EKS-optimised AMI, and trigger a safe rolling node replacement.

---

## Table of Content

- [Threat Modelling](#threat-modelling)
- [Kubernetes Security Controls](#kubernetes-security-controls)
- [Policy as Code](#policy-as-code)
- [Secrets Management and TLS](#secrets-management-and-tls)
- [Runtime Security with Falco](#runtime-security-with-falco)
- [AWS Foundation and Network Security](#aws-foundation-and-network-security)
- [Patch Management, SSM Session Logging, and ECR Hardening](#patch-management-ssm-session-logging-and-ecr-hardening)
- [AWS Logging, Monitoring, and Detection](#aws-logging-monitoring-and-detection)
- [EventBridge and Lambda Automated Remediation](#eventbridge-and-lambda-automated-remediation)
- [Observability and Monitoring](#observability-and-monitoring)
- [Branch Protection, AWS OIDC, and Workflow IAM Roles](#branch-protection-aws-oidc-and-workflow-iam-roles)

---

## Threat modelling

I implemented shift left security principle to identify and mitigate threats at design time rather than discovering them after deployment. I started with threat modeling of every component of the security architecture, including actors, data flows, processes, and data stores. This was to understand what I’m building, what can go wrong, and how it can be mitigated which drives every architectural decision. 

This threat model covers 47 threats across all six STRIDE categories applicable to this architecture. I applied DREAD scoring for risk quantification and NIST CSF mapping for compliance alignment. I did a risk analysis with mitigated risks, residual risks and accepted gaps documented.


**Threat Model Summary**

| ID | Component | STRIDE | DREAD | Risk | Threat Summary | Key Controls |
|----|-----------|--------|-------|------|----------------|--------------|
| T4 | User HTTP Traffic | Tampering | 23 | CRITICAL | SQL injection and XSS payloads in HTTP requests | AWS WAF, PSA Restricted, OPA Gatekeeper |
| T23 | DVWA Pod | Elevation of Privilege | 17 | HIGH | Container escape through runtime vulnerability | PSA Restricted, Falco, Falco Sidekick |
| T9 | CI/CD Pipeline | Tampering | 18 | HIGH | Malicious workflow pushed directly to main branch | Workflow seperation with leas privilege IAM roles, Branch protection, Checkov, Cosign |
| T45 | EC2 IMDS | Elevation of Privilege | 17 | HIGH | Container escape queries IMDS for node IAM credentials | IMDSv2, node least privilege, Falco |
| T14 | SSM Session Manager | Tampering | 17 | HIGH | Valid SSM access used to disable Falco or alter node state | IAM condition keys, keystroke logging, Falco |
| T7 | Pod-to-Pod Traffic | Tampering | 13 | MEDIUM | Compromised DVWA pod sends malicious queries to drop tables or escalate database privileges | NetworkPolicy default-deny, database privilege restriction |
| T12 | Pod-to-AWS API (IRSA) | Information Disclosure | 15 | MEDIUM | IRSA token stolen from pod filesystem and used outside the cluster to access AWS resources | IRSA token expiry, VPC CIDR-scoped trust policy |
| T37 | Vault | Information Disclosure | 17 | HIGH | Vault storage backend compromise reveals all stored secrets in plaintext | KMS auto-unseal, AES-256-GCM encryption, TLS 1.3, path-scoped policies |

*For a detailed insight on the complete threat model with DREAD scoring, risk matrix and risk posture summary, view in the Google Sheet below.*

[Threat Model](https://docs.google.com/spreadsheets/d/1aVw7FQazMh0S7U9Myd2VGUARhMJFIJVE/view?usp=sharing)


---

## Kubernetes Security Controls

I started with creating Kubernetes manifests for DVWA and MariaDB, and verified connectivity before adding any security controls. 

Initially, while in Minikube for local testing, I deployed both pods in the same "production" namespace because they are web and database tiers of the same application. At a later stage, I separated them into different namespaces to enforce hardened network policies, isolate blast radius, implement dedicated service accounts for granular identity and least privilege access control, and for resource management with different limit ranges at the namespace level based on requirement.

### A: Kubernetes Pod Security Standard

To mitigate the risk of a container runtime vulnerability such as a runc CVE or dirty-pipe class exploit that can allow an attacker to escape the container and access the underlying EKS worker node or an attacker with Kubernetes API access modifying a running pod specification to inject privileged capabilities, mount the host filesystem, or insert malicious code, I enforced the Kubernetes Restricted Pod Security Standard Profile on [DVWA](k8s/dvwa/dvwa.yaml) and [Database](k8s/database/mariadb.yaml) namespaces. 

This will prevent any of the container processes from gaining more privileges than it started with, block the container from running as root because if a root process inside a container escapes the container boundary and lands on the node as root, it gives the attacker immediate control of the node. It will also drop all linux capabilities which are granular units of root privilege so that non of the containers can perform privileged operations even while running as a non-root user, blocks dangerous Linux system calls that the containers have no legitimate reason to invoke, and blocks hostPath mounts, hostNetwork, and hostPID.

Any pod that does not meet these requirements is rejected at admission.

### B: Extra kubernetes security controls

On top of what the restricted profile mandates, I implemented the following controls for defense-indepth

- runAsUser: 999 on MariaDB and runAsUser: 998 on DVWA. This will prevent permission errors and avoid any ambiguity about which user the process identity should resolve to.

- fsGroup: 999 on MariaDB with fsGroupChangePolicy: OnRootMismatch. Because the MariaDB pod will require exclusive ownership of its data directory and without correct ownership, will refuse to start because it cannot read or write its own data files. I configured fsGroup: 999 to allow Kubernetes set the PersistentVolume group ownership before the container starts, avoiding the need for CHOWN capability which is a privileged operation to fix permissions. The *fsGroupChangePolicy: OnRootMismatch* will ensure that ownership is only changed if it does not already match to avoid unnecessary recursive permission operations on large volumes.

- readOnlyRootFilesystem: true on both pods. I mounted the container filesystem for both pods as read-only. This will prevent a compromised container from writing malicious binaries, modifying application code, or staging exfiltrated data anywhere on its own filesystem outside of explicitly defined writable mounts. This directly reduces the blast radius if a compromise is successful, addressing the threats of an attacker escaping the container, or the database files being modified to inject backdoors or corrupt audit records.

- emptyDir volumes: The readOnlyRootFilesystem that I enabled required that I mount emptyDir volumes at every path the applications need to write to at runtime.

- Resource limits and requests on both pods: CPU and memory limits will prevent any single workload from exhausting the node resources, I also configured limit ranges for [DVWA](k8s/dvwa/limitrange.yaml) and [MariaDB](k8s/database/limitrange.yaml) namespaces as a safety net to enforce default resource requests and limits on any container that does not explicitly define them. These addresses the threat of a memory leak or deliberate resource bomb exhausting available node resources and causing pod evictions, pending states and service unavailability.

-  Readiness and Liveness probes on both pods:
I configured readiness probes to ensure that the applications pods are ready before kubernetes starts sending in traffic, and liveness probes to detect when a container is running but is no longer responding to requests which can provide automated self healing for the pod by kubernetes restarting the pod. 

- On DVWA, I configured readiness probe on /login.php and liveness on /. This is because readiness */login.php* requires the full stack to be available (Apache, PHP, and the database connection), so traffic will not be sent to DVWA if MariaDB is unavailable. For liveness probe, I used / so that if MariaDB is temporarily unavailable, Kubernetes will not restart DVWA unnecessarily when Apache is healthy.
  
```yaml
readinessProbe:
  httpGet:
    path: /login.php
    port: 80
  initialDelaySeconds: 10
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3
livenessProbe:
  httpGet:
    path: /
    port: 80
  initialDelaySeconds: 60
  periodSeconds: 30
  timeoutSeconds: 10
  failureThreshold: 3
```
  
- For MariaDB, I configured exec probes that runs mysqladmin ping using the dedicated healthchecks. I created the dedicated healthcheck user using an init script. I generated a strong password using openssl rand number generator, stored the password in Vault which is synced to kubernetes secrets by ESO for MariaDB to access it through environment variable. This is consistent with the no hardcoded secret security principle.

- I didn’t enable vault auto rotation because liveness probes runs every few seconds. If the probe fails because the dynamic rotation handshake experienced a latency, kubernetes will assume the container is dead and unnecessarily restart the pod making the database appear unavailable.

- I created a dedicated healtchcheck user rather than reusing the application credentials because a dedicated user with minimal privileges follows the priciple of least privilege and will limit what an attacker can access if they observe the probe command.
  
- I also implemented password requirement for the dedicated healthcheck user to mitigate lateral movement. Although the user is restricted to localhost, all containers in a pod share the same network namespace and therefore the same localhost. If I add a sidecar to the MariaDB pod in future, it would inherit localhost trust. Without a password, any process in the pod could connect to MariaDB as the healthcheck user with no barrier.

- I configured the readiness and liveness probes for MariaDB to use -h 127.0.0.1 rather than -h localhost. This is because when -h localhost is used, MariaDB connects via a Unix socket and applies unix_socket authentication based on the Linux system user identity. Since the health check database user is not the system user, authentication fails regardless of the password. Using -h 127.0.0.1 forces TCP/IP, which always utilizes password authentication.

- However, simply creating the user with an IDENTIFIED VIA mysql_native_password clause alone was not sufficient because the initial database provisioning defaults new local accounts to the unix_socket authentication plugin, bypassing the password validation required by the probes. I resolved this by using a shell Heredoc file during the initialization stage to execute an explicit ALTER USER statement immediately after creation, this forcefully resets the health check user's authentication plugin back to mysql_native_password.

- Also, to securely execute these administrative modifications during the init phase, I passed the root credentials through the MYSQL_PWD environment variable instead of using the standard -p command-line flag. This prevents exposing the plaintext credential to the host operating system's process table and restricts the secret strictly to the process environment memory space.

```yaml
data:
  init.sh: |
    #!/bin/sh
    MYSQL_PWD="${MARIADB_ROOT_PASSWORD}" mysql -u root <<EOF
    CREATE USER IF NOT EXISTS 'healthcheck'@'127.0.0.1' IDENTIFIED BY '${HEALTHCHECK_PASSWORD}';
    CREATE USER IF NOT EXISTS 'exporter'@'127.0.0.1' IDENTIFIED BY '${EXPORTER_PASSWORD}' WITH MAX_USER_CONNECTIONS 3;
    ALTER USER 'healthcheck'@'127.0.0.1' IDENTIFIED VIA mysql_native_password USING PASSWORD('${HEALTHCHECK_PASSWORD}');
    ALTER USER 'exporter'@'127.0.0.1' IDENTIFIED VIA mysql_native_password USING PASSWORD('${EXPORTER_PASSWORD}');
    GRANT PROCESS, REPLICATION CLIENT ON *.* TO 'exporter'@'127.0.0.1';
    GRANT SELECT ON performance_schema.* TO 'exporter'@'127.0.0.1';
    REVOKE ALL PRIVILEGES ON dvwa.* FROM '${MARIADB_USER}'@'%';
    GRANT SELECT, INSERT, UPDATE ON dvwa.* TO '${MARIADB_USER}'@'%';
    DROP USER IF EXISTS 'root'@'%';
    FLUSH PRIVILEGES;
    EOF
```

**Database privilege restriction** 

- By default, MariaDB grants the application user full privileges on the database. I implemented an init script that revokes these and grants **ONLY** SELECT, INSERT, UPDATE permissions on the dvwa database user. This addresses the threat of a compromised DVWA pod sending malicious SQL queries attempting to drop tables, exfiltrate data, or escalate database privileges. I intentionally ommitted the DELETE permission because a compromised application pod with DELETE permission can delete users, wipe access logs, or destroy audit records. In production, DELETE operations such as log rotation would be handled by a dedicated maintenance database user triggered by a scheduled cron job, not available to the application at runtime. 

- I restricted Root user to localhost only so that all database administration will require kubectl exec into the pod, which is logged on Kubernetes audit logs. This will prevent the risk of if port 3306 were ever accidentally exposed through a misconfigured NetworkPolicy or a cloud security group, an attacker cannot authenticate directly as root from outside the cluster.

- I also configured the mysqld-exporter user with only the minimum permissions needed to scrape meaningful database metrics without exposing the ability to read application data or modify database state. I capped the connection pool at 3 to prevent the exporter from exhausting database connections under load, which would degrade application performance or trigger a denial of service against MariaDB.

**ConfigMap and manifest tampering**

- At this stage, anyone with kubectl write access to the database namespaces can apply any manifest including creating or modifying ConfigMaps. I intend to close the gap by implementing branch protection with GPG-signed commits, Pod ServiceAccounts having zero API permissions, IAM scoped kubectl access alongside OPA Gatekeeper constraint to reject manually created or updated ConfigMaps and strictly force all manifest deployment or edit to go through GitOps pipeline.

**StatefulSet for MariaDB and Deployment for DVWA**

- I configured MariaDB as StatefulSet because it is a database that requires a PersistentVolume for the database files, the pod needs a stable and predictable identity so that the volume claim can always reattach to the correct pod on restart. A StatefulSet provides this stable identity and manages the PersistentVolumeClaim lifecycle. 
In contrast, I configured the DVWA pod as a Deployment because it is stateless and each replica is interchangeable without the risk of a pod restarting without reattaching to the same volume.

### C: RBAC: Dedicated ServiceAccount per workload

I created dedicated for dvwa and MariaDB with empty Roles granting zero Kubernetes API permissions because neither pod needs to call the Kubernetes API. The dedicated identity ensures that audit logs are recorded separately for each ServiceAccount, and permissions can be adjusted per workload independently without affecting the other. This directly addresses the threat of a stolen Kubernetes service account token being used to impersonate an administrator and perform unauthorised cluster operations, or a service account with limited permissions exploiting a Kubernetes vulnerability to escalate to cluster-admin. Because ServiceAccounts are mounted at the pod level, not the container level, every container in a pod inherits the same ServiceAccount token. If a pod had multiple containers with different trust levels, the less trusted container would inherit the same token as the more privileged one. 

I configured *automountServiceAccountToken: false* for both pods because even with the dedicated ServiceAccounts and empty roles, the token is still mounted into the pod filesystem by default, and if an attacker gains code execution inside DVWA or MariaDB, they can read that token and use it to authenticate to the Kubernetes API directly and be able to perform reconnaissance inside the cluster.

### D: NetworkPolicy

- I configured default deny network policies in [database](k8s/database/network-policy.yaml) and [dvwa](k8s/dvwa/network-policy.yaml) namespaces and then allowed only the required traffic.

- I allowed ingress to the database only from the application pod on port 3306 for query response and the Prometheus pod on port 9104 for metrics scraping. I allowed egress only to the kube dns ON PORT 53 for dns resolution.

- For the dvwa namespace, I allowed ingress only on port 80 from the application load balancer and egress only to the database on port 3306 for querying and to kube DNS on port 53

- I configured the network policies with namespace and pod selectors to ensure granular security. The network policies by isolating the database traffic to only dvwa, addresses the threat of an unencrypted database connection revealing passwords or query content to a malicious pod on the same node. By denying all egress except for DNS and MariaDB, the network policy with the RBAC configuration of minimal role service accounts, address the threat of a stolen service account token being used to call the Kubernetes API server from inside a pod.
  

**NetworkPolicy label spoofing**
  
- The Network Policies select pods by label, this means that any pod created in dvwa namespace with a matching label will inherit the same network access rules including egress to MariaDB on port 3306. The current control is RBAC, both pod ServiceAccounts have zero API permissions, so an attacker cannot create malicious pods from a compromised container through the Kubernetes API using its token but someone with kubectl access can. This is a gap at this stage which I will mitigate in future stages with Cosign image signing and OPA Gatekeeper admission constraint that will block any pod with an unsigned image regardless of what labels it carries. I will also mitigate the risk of maliciously deploying the exact signed image by using IAM scoped kubectl access to prevent unauthorized kubectl access.

---

## Policy as Code

- I implemented OPA Gatekeeper with custom Constraints and Templates using Rego to serve as an admission control policy as code to enforcing security requirements, and catching misconfigurations before any workload can be admitted into the cluster. I configured all Constraints to target both naked Pods and controller resources so that every resource is intercepted irrespective of how it is applied. 


**NetworkPolicy** *[Templates](k8s/opa_gatekeeper/01-templates/enforce_network_policy.yaml)* and *[Constraint](k8s/opa_gatekeeper/02-constraints/network_policy_constraint.yaml)*:

- Although PSS restricted profile controls pod security context, it doesn’t enforce network isolation and least privilege network connectivity. With this enforcement, any pod submitted to a namespace without a default deny network policy that selects all pods and covers both ingress and egress traffic will be blocked at admission.I used nested object.get calls rather than direct path access because direct path access will return undefined for namespaces with no networking resources defined which will cause the Rego rule to fail silently.

```yaml
 targets:
   - target: admission.k8s.gatekeeper.sh
     rego: |
       package enforcenetworkpolicy
       violation[{"msg": msg}] {
         ns := input.review.object.metadata.namespace
         policies := object.get(object.get(data.inventory.namespace, ns, {}), "networking.k8s.io/v1", {})
         networkpolicies := object.get(policies, "NetworkPolicy", {})
         valid_deny_policies := [p |
           p := networkpolicies[_]
           is_default_deny(p.spec)
         ]  
         count(valid_deny_policies) == 0
         msg := sprintf("Namespace '%v' does not have a network policy", [ns])
       }

       is_default_deny(spec) {
         object.get(spec, "podSelector", {}) == {}
         types := object.get(spec, "policyTypes", [])
         has_item(types, "Ingress")
         has_item(types, "Egress")
       }

       has_item(arr, item) {
         arr[_] == item
       }
```

- To enforce the network policy, I configured the [config file](k8s/opa_gatekeeper/00-setup/sync.yaml) for OPA Gatekeeper to enable it sync network policies from *data.inventory* because without it, Gatekeeper as an admission controller can only inspect the resource currently being submitted.


**RBAC ServiceAccount** *[Template](k8s/opa_gatekeeper/01-templates/enforce_rbac_service_account.yaml)* and *[Constraint](k8s/opa_gatekeeper/02-constraints/rbac_service_account_constraint.yaml)*:

- I configured four violation blocks that targets Pods, Roles, ClusterRoles, RoleBindings and ClusterRoleBindings. Blocks 1 and 2 ensure that every resource has a dedicated ServiceAccount that is not the default service account, addressing the threat of a compromised pod inheriting excessive API permissions through the default account (even if someone grants an excessive permission to the default account). Block 3 blocks RoleBindings/ClusterRoleBindings that grant cluster-admin, admin or edit roles which are dangerous built-in roles that grant broader permissions than any application workload will require. Block 4 blocks wildcard permissions on Role/ClusterRole verbs, resources and apiGroups because a wildcard on any single dimension can grant excessive permissions regardless of what the others restrict.

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

      wildcard(rule) { rule.verbs[_] == "*" }
        wildcard(rule) { rule.resources[_] == "*" }
        wildcard(rule) { rule.apiGroups[_] == "*" }

        get_pod_spec(obj) = spec {
          obj.kind == "Pod"
          spec := obj.spec
        }

        get_pod_spec(obj) = spec {
          spec := obj.spec.template.spec
        }

```

**Resource Limits** *[Template](k8s/opa_gatekeeper/01-templates/require_resource_limits.yaml)* and *[Constraint](k8s/opa_gatekeeper/02-constraints/require_resource_limits_constraint.yaml)*:

- Without this limit, an attacker can utilize a deliberate resource bomb to exhaust available node resources and cause a denial of service.


**NonRootUser** *[Template](k8s/opa_gatekeeper/01-templates/enforce_non_root.yaml)* and *[Constraint](k8s/opa_gatekeeper/02-constraints/runasnonroot_constraint.yaml)*

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

- The first block catches when run as non root is not enforced either at the pod or container level. The second block catches when the container level tries to override run as non root user enforced at the pod level. The third and fourth blocks will catch when UID of 0 is explicitly assigned to either the pod or container.


**DenyPrivilegedContainer** *[Template](k8s/opa_gatekeeper/01-templates/deny_privileged_containers.yaml)* and **[Constraint](k8s/opa_gatekeeper/02-constraints/deny_privileged_containers_constraint.yaml)*

**ReadOnlyRootFilesystem** *[Template](k8s/opa_gatekeeper/01-templates/read_only_root_fs.yaml)* and *[Constraint](k8s/opa_gatekeeper/02-constraints/readonly_root_fs_constraint.yaml)*

**BlockLatestImageTag** *[Template](k8s/opa_gatekeeper/01-templates/block_latest_image.yaml)* and *[Constraint](k8s/opa_gatekeeper/02-constraints/block_latest_image_constraint.yaml)*: 

- I scoped this to dvwa and database namespaces only so as to prevent applications from automatically pulling a new image on pod restart which could introduce untested changes without a deployment pipeline. However, an engineer may need to legitimately use kubectl run without specifying a tag for quick testing. By scoping this constraint to production namespace, it preserves workflow flexibility outside production while enforcing stability where it matters. 


**I validated all these rules by applying a non complaint pod**

![opa gatekeeper violation](screenshots/phase1/opa_gatekeeper_violation.png)

---

## Secrets Management and TLS

- I configured [Vault](k8s/vault/vault-values.yaml) with [ESO](k8s/eso/eso-values.yaml) for secrets management. This prevents hardcoding of secrets in config files, manifests or any source codes. Vault stores secrets encrypted at rest with a full audit log of every read, write, and authentication event. It follows the principle of least privilege because acess is controlled by policies that restrict exactly which paths a client can read.

- In a production environment, I would store the Vault root token I generated during initialisation in a break-glass account and never to be used for day-to-day administration because the root token has unrestricted access to every Vault path and operation. I would integrate Vault with an identity provider like Okta so engineers can authenticate to Vault using their corporate identity with MFA enforced, and access governed by role-based policies. This will make every Vault operation attributable to an identity.

- I implemented ESO as the only client that can connect directly to Vault. I chose ESO to completely isolate application pods from Vault at runtime. Neither of the pods hold Vault tokens, can authenticate to Vault, or have any knowledge of the secrets backend; they read normal Kubernetes Secrets that ESO manages on their behalf. This eliminates the risk of Vault token being exposed through application vulnerabilities. It also removes the need for Vault Agent sidecars in every pod, and enforces a strict separation between infrastructure secret management and application runtime.

- I created a path scoped read-only ESO policy with a dedicated vault role for each path that grants ESO read access only to the allowed secret path.

**SecretStore and ExternalSecret**
  
- I configured namespace restricted Secret Stores for for [dvwa](k8s/dvwa/dvwa.yaml), [database](k8s/database/database-secret-store.yaml), [mysqld](k8s/database/monitoring-secret-store.yaml), and [Grafana Admin](k8s/observability/observability-secretstore.yaml) secrets. A namespaced SecretStore cannot be used by other namespaces, which prevents a compromised pod in a different namespace from leveraging it to read secrets from another namespace. For mariadb pod and the mysqld-exporter which lives in the same namespace, I implemented least privilege by configuring different secrets stores and eso roles for them, restricting their access to their specific secret paths

- I enabled a refreshInterval of 1h on the external secret so that ESO polls Vault every hour. If the password is rotated in Vault, ESO will automatically update the secrets within the hour without requiring the pods to restart.

- In this development environment where I do a daily destroy of the infrastructure for cost management, key rotation is not critical. So, I used static keys stored in Vault KV for the database root password, application database user, mysqld-exporter credentials, and Grafana admin password. ESO syncs these into Kubernetes Secrets which the pods consume at runtime eliminating hardcoded credentials in manifests or values files.

- In a production environment where static credentials can introduce critical risks like credential theft, insider threat, and long exposure windows, I would enable the Vault Database Secrets Engine and configure Vault to take ownership of the database root password. With this, Vault can generate a complex random password, store it internally, and overwrite the original used in init phase. This will eliminate any engineer or admin knowledge of the root password. It can only be accessed when necessary through Vault's API by an authenticated identity with explicit policy permission and access captured in audit logging.

- I would also enable dynamic generation of short-lived database user credentials on request using Vault's dynamic roles. When ESO syncs the ExternalSecret, it requests credentials from Vault, Vault connects to MariaDB and creates a temporary user with time-to-live, ESO will then write the credentials into a Kubernetes Secret so that MariaDB can consume. This will eliminate re-using of credentials and limit the attack window from a stolen token.

**Network policy for ESO and Vault**

- I applied default-deny-all NetworkPolicy to both the [Vault](k8s/vault/network-policy.yaml) and [ESO](k8s/eso/network-policy.yaml) namespaces, then explicitly allowed only the traffic each pod needs.

- **Vault ingress**: I allowed ingress on port 8200 from the ESO namespace only, restricted to the ESO pod label so that only ESO can reach the Vault API. In a case of ESO or another namespace compromise, no other pod or namespace can authenticate to Vault. I also allowed ingress on port 8200 from Prometheus in the observability namespace for metrics scraping.

- **Vault egress**: I allowed egress to CoreDNS on port 53 for DNS resolution. For KMS and STS I used toCIDRSet with the exact private VPC endpoint IPs. I allowed egress to kube-apiserver Entity on port 443 for Vault's Kubernetes auth method. 

- **ESO ingress**: I allowed ingress on port 10250 from kube-apiserver for the ESO webhook to allow the Kubernetes API server call the ESO webhook to validate ExternalSecret and SecretStore resources before they are admitted to the cluster. I switched from the VPC CIDR 10.0.0.0/16 to kube-apiserver entity because the VPC CIDR is too broad and would allow any resource in the VPC to call the webhook port. I didn't use IP because the stability of the control plane X-ENI IPs used for webhook ingress is not guaranteed, making the entity-based approach more reliable. I allowed ingress on port 8080 from Prometheus for metrics scraping.

- **ESO egress**: I allowed egress to CoreDNS on port 53 for DNS resolution. I allowed egress to Vault on port 8200, restricted to the vault namespace and pod label. I also allowed egress to kube-apiserver on port 443 to allow ESO to watch ExternalSecret and SecretStore custom resources, create and update Kubernetes Secrets, and Validate Webhook configuration updates through the cert-controller.

**ESO to Vault TLS**

- I enabled ESO to Vault traffic to run over TLS using [self-signed cluster issuer](k8s/cert-manager/cluster-issuer.yaml) and cert manager. This follows Zero Trust principle because if the traffic is unencrypted, an attacker with network access inside the cluster can intercept credentials in transit without needing to compromise either service.

- I initially used kubernetes reflector to reflect the [Vault](k8s/cert-manager/vault-certificate.yaml) certificate to ESO namespace. I moved away from it because it mirrors the entire Kubernetes Secret, which for a TLS certificate, includes the private key alongside the public certificate which ESO needs. Distributing the private key to the ESO namespace unnecessarily is a real exposure where if the ESO namespace is compromised, the attacker gets the private key and can impersonate Vault.

- I resolved to using [Trust manager](k8s/cert-manager/trust-manager-values.yaml) which distributes only the public certificate into a ConfigMap in the ESO namespace.  I also scoped the trust bundle distribution to only the ESO namespace following the principle of least privilege.

- This encryption is at the application layer. In a Zero-trust production environment with many microservices, I can enable Vault PKI and configure Vault as an intermediate CA to provide dynamic certificate for the cluster service mesh for mutual authentication and network level encryption of all microservices connection.

**Vault IRSA, KMS and Audit Logging**
  
- I deployed Vault on EKS in the isolated node group. I configured it to use AWS KMS for auto-unseal on every pod restart using the IRSA to call KMS to decrypt its own root encryption key and unseal itself automatically without any human intervention. View [IRSA](terraform/modules/eks/irsa.tf) and [KMS](terraform/modules/eks/kms.tf) config 

- I attached the KMS unseal key permission on Vault's dedicated IRSA role and not the node's IAM role. This eliminates the risk of a compromised MariaDB pod which runs in the same node inheriting the permission to call KMS and potentially unseal Vault from the outside. The KMS key policy also provides a second enforcement layer that restricts which IAM principal can use the key.

- I also configured Vault file audit backends to write to the Vault pod's local filesystem. With this enabled, every request and response Vault processes is logged in structured JSON with HMAC-hashed tokens, so the audit trail cannot be tampered without detection.

![vault audit](screenshots/phase2/vault_audit.png)

*vault audit logging*


- In production I would configure the file backend to ship to an SIEM tool for monitoring, compliance reporting, and correlation with other security events. I would also configure a second syslog backend with an rsyslog sidecar, to ship audit events to Loki through Alloy for real-time correlation in Grafana alongside application logs and Falco alerts.

- The two backends will also prevent an attacker from exploiting the default fail-closed nature of Vault's audit system which blocks the request entirely if the audit backend is unreachable thereby causing a DoS.

---

## Runtime Security with Falco

- I configured falco for runtime security, I enabled the least-privilege flag to strip away unnecessary administrative root access (CAP_SYS_ADMIN), restricting the container to only the specific eBPF capabilities it needs to monitor system events. I also excluded the falco namespace from some OPA Gatekeeper policies because falco needs access to the host kernel to monitor syscalls. 

- Following the principle of least privilege, I only excluded the falco namespace from the three minimum necessary policies it needs to function while leaving others (resource limits, NetworkPolicy enforcement, RBAC enforcement) active. I also did not label the falco namespace with PSA Restricted for the same reasons because the restricted profile would block Falco's privileged containers at admission. 

**[Falco Custom Rules](k8s/falco/falco-eks-values.yaml)**

- *Shell Spawned in Container rule:* The default Falco rule for terminal shell in container only fires when a shell is spawned with an interactive terminal attached. This would miss a common attack pattern where an attacker could exploit a web application vulnerability and use sh -c without an interactive terminal. I excluded the proc.tty requirement in my custom rule to catch that. I also excluded the MariaDB health check probe which legitimately spawns sh -c mysqladmin ping and Vault which often runs status checks. By requiring both the mariadb image and mysqladmin in the command line to match, I made it harder to abuse it as an evasion path.

```yaml
 - rule: Shell Spawned in Container
     desc: A shell process spawned inside a running container.
     condition: >
       spawned_process and
       container and
       shell_procs and
       not proc.pname in (shell_procs) and
       not user.name = healthcheck and
       not (container.image.repository = mariadb and proc.cmdline contains mysqladmin) and
       not (container.image.repository contains "hashicorp/vault" and proc.cmdline contains "vault status")
     output: "Shell spawned in container (user=%user.name container=%container.name image=%container.image.repository shell=%proc.name parent=%proc.pname cmdline=%proc.cmdline namespace=%k8s.ns.name pod=%k8s.pod.name)"
     priority: WARNING
     tags: [container, shell]
```
- *Security Agent Termination Attempt rule:* I added this as a tripwire for an attacker attempting to disable security monitoring before performing malicious activity. This rule fires before Falco is killed, this will give Sidekick a window to respond and also will alert the security team even if the kill attempt ultimately succeeds.

```yaml
- rule: Security Agent Termination Attempt
    desc: An attempt was made to terminate the Falco security monitoring process.
    condition: >
      spawned_process and
      proc.name in (kill, pkill, killall) and
      proc.cmdline contains falco
    output: "Falco agent termination attempt detected (user=%user.name process=%proc.name cmdline=%proc.cmdline container=%container.name namespace=%k8s.ns.name pod=%k8s.pod.name)"
    priority: CRITICAL
    tags: [falco, tamper]
```

- *Privilege Escalation Syscall in Container rule:* Container escape exploits and various runc CVEs work by exploiting a vulnerability to call setuid(0) and gain root inside the container before breaking out. Monitoring setuid and setgid syscalls from non-root processes will give early warning of this pattern. I excluded runc because the container runtime legitimately calls setuid during container initialisation.

```yaml
- rule: Privilege Escalation Syscall in Container
    desc: A process executed a setuid or setgid syscall inside a container.
    condition: >
      container and
      evt.type in (setuid, setgid) and
      not user.uid = 0 and
      not (proc.name startswith runc and proc.cmdline contains init) and
      not (container.image.repository contains "hashicorp/vault" and proc.cmdline contains "vault status")
    output: "Privilege escalation syscall in container (user=%user.name uid=%user.uid container=%container.name image=%container.image.repository syscall=%evt.type cmdline=%proc.cmdline namespace=%k8s.ns.name pod=%k8s.pod.name)"
    priority: CRITICAL
    tags: [syscall, privilege_escalation]
```

**[Initial Falco Custom Rules](k8s/minikube/falco-values.yaml)**

- Initially, while on minikube with calico cni, I added some custom macros to my falco rules based on the environment which I later removed when I moved to AWS environment with cilium CNI.

- *calico_cni macro:* Calico runs as a DaemonSet and makes frequent outbound connections as part of its normal networking operations including health checks to its own Felix component on port 9099, DNS queries, and Kubernetes API calls during pod network setup. Without this macro my outbound rules would flood with Calico false positives which can make real alerts invisible. I scoped the macro to cover all Calico components as well as Falco which also makes legitimate outbound connections.

```yaml
 - macro: calico_cni
   condition: proc.exepath startswith /opt/cni/bin/ or
     container.image.repository = quay.io/calico/node or
     container.image.repository = quay.io/calico/kube-controllers or
     container.image.repository = falcosecurity/falco
```
- *known_drop_and_execute_activities macro:* This is the default Falco macro that the Executing binary not part of base image rule checks against. Calico's CNI binaries live at /opt/cni/bin/ on the host and execute during pod network setup, Falco sees them as binaries that are not part of any container image and fires alerts constantly. I overrode it to add Calico CNI paths to prevent log flooding.

```yaml
- macro: known_drop_and_execute_activities
  override:
    condition: append
  condition: >
    or proc.name in (calico, portmap)
    or proc.exepath startswith "/opt/cni/bin/"
```
- *outbound macro:* I rewrote this macro rather than using the default because the default Falco outbound macro explicitly excludes all RFC1918 private IP ranges. This means the default macro would ignore every connection within the Kubernetes cluster since all pod and service IPs fall in RFC1918 space. I removed the RFC1918 exclusion and replaced it with a loopback exclusion fd.net != "127.0.0.0/8" to keep health check connections to 127.0.0.1 out of scope while making sure all real cluster traffic is monitored.

- I removed this rule in AWS environment because monitoring all internal cluster traffic would lead to alert fatigue because hundreds of containers continuously make outbound connections within the cluster.

- I triggered the rules to confirm that falco is correctly firing the alerts.
- 
![Falco Firing](screenshots/phase1/falco_test.png)

**Falco Sidekick**

- Falco sidekick doesn’t require any privileged capability, so I enforced least privileged security context on the pod. This prevents it from inheriting the privileges from Falco pod. In a production environment, I will install them as separate Helm charts for absolute separation of privileges.

- I initially deployed Falco sidekick for automated threat response; to delete pods when a critical violation is confirmed. l limited this capability to the application namespace to prevent it from being abused if the Sidekick pod is compromised. 

- I removed this capability later because pod deletion is a critical capability. In a production environment, it can be enforced after observing and establishing baseline threat detection and behavioral monitoring to avoid acting on false positives.  


**Falco[NetworkPolicy](k8s/falco/falco-network-policy.yaml)**:  

- I wrote three policies for the falco namespace; a default deny covering all pods as the baseline, a Falco specific policy, and a Sidekick specific policy using pod label selectors so that each component only has the access it needs.

- **Egress rule** on port 53 covering both pods for DNS name resolution
  
- **Falco pod ingress rule** only on port 8765 for metrics scraping.

- **Falco pod egress rule** on port 443/TCP for falcoctl rule updates with the FQDNs of the required sites to ensure that falco rule update process can only reach the official Falco security distribution endpoints and cannot be hijacked to pull rules from an attacker-controlled source, and egress on port 2801/TCP to falco sidekick pod selector for forwarding Falco alerts to sidekick. 

- **Sidekick pod ingress rule** allows 2801/TCP from Falco pod label only, which will prevent any other pod from sending fake alerts to falsely trigger pod deletions, and ingress on port 2801 from prometheus for metrics scraping.

- **Sidekick pod egress rule** allows egress on port 80 to loki svc port for forwarding structured falco alerts to loki for visualization and monitoring on grafana dashboard.

---

## AWS Foundation and Network Security

**Cost Management**
  
- Before provisioning anything I configured billing alerts. Since I planned to destroy and recreate infrastructure daily to manage my AWS credits, I needed visibility into any unexpected charges. In production, this is critical because unmonitored cloud spend can lead to budget overruns. Cost anomaly detection specifically catches unusual spending patterns that total budget alerts miss which is vital because unexpected cost spikes are also a potential indicator of compromise like an attacker spinning up EC2 instances.

**Terraform State**
  
- I created the DynamoDB table for state locking and the terraform state bucket. Because I planned to run terraform destroy at the end of every work day to save cost, I could not manage the S3 state bucket and DynamoDB lock table with Terraform. I created both manually through the AWS CLI so they can survive daily destroy cycle. 

- I enabled versioning on the state bucket so I can recover from a corrupted state file or accidental delete, and blocked public access because the state file stores the entire inventory of my architecture in plaintext and if someone has an unauthorized access to it, they can map my entire attack surface.

- I enabled a customer managed KMS key rather than the default AWS managed encryption. The default encryption still allows anyone with basic S3 read permissions in my account to view the contents. With a CMK, even if someone gains S3 access, they cannot read the state file without also having permission to use the specific KMS key. It also provides an audit trail of every time terraform reads or writes to the state file. 

- I created a dedicated Terraform IAM user with least privilege permissions rather than using the root account for day-to-day infrastructure management. Root has unrestricted control over the entire account and using it directly is a significant risk because a compromised root session has no blast radius boundary. In a production environment, I would replace the IAM user with an IAM role because IAM users use long-lived access keys that can be leaked or stolen. A role-based approach uses STS to generate short-lived temporary credentials that expire automatically, which will eliminate the risk of a leaked key providing persistent access. I would then configure the Terraform S3 state bucket policy to restrict access to that specific role ARN, and enforce MFA on any principal allowed to assume it.

**Three-Tier VPC**
  
- I built the [VPC](terraform/modules/network/vpc.tf) with three subnet tiers across three availability zones. The public subnets [route](terraform/modules/network/routing.tf) to the Internet Gateway, the private and the isolated subnets route to the NAT Gateway. I intended to configure the isolated subnet to have no internet route at all, but I implemented EKS Managed Node Groups for this project, and deploying nodes into a strictly isolated subnet without internet connectivity requires self-managed mode for the node group to be able to join the cluster.

- For a production environment with strict requirement for no internet access and to eliminate the risk of making outbound connection in the case of a compromise, I would configure the Self-managed node mode through the node user data bootstrap configuration, in isolated subnets with AWS VPC Endpoints. This will allow the worker node group to join the cluster, and the nodes to securely communicate with the EKS control plane, and internal infrastructure entirely over the AWS private network.
  
- This network segmentation separates the public facing workloads and private internal workloads. I provisioned the load balancer in the public subnet and is the only resource that has direct access from the internet while the application and observability node will live in the private subnet.

- The isolated node will live separately in the isolated subnet because I provisioned database and vault which hold the raw data and the master cryptographic encryption keys in it, I also configured the nodes with taint, to prevent any pod without the appropriate toleration from being scheduled together with vault and database. This ensures that even if an attacker deploys a malicious pod into the cluster, it cannot land on the isolated node and attempt local attacks against Vault or the database through shared node resources.

- I provisioned one NAT gateway in just one availability zone for cost management. In a production environment, each AZ should have its own NAT gateway for high availability.

**[Security Groups](terraform/modules/network/security.tf)**
  
- I configured security groups for micro-segmentation. I restricted the ALB SG ingress traffic to port 80 and 443. I also configured at the ALB listener level, HTTP redirect to HTTPS before any content is served. I combined it with HSTS to instruct browsers to never attempt an HTTP connection to my domain. This ensures that no unencrypted traffic can reach the application which will eliminate the risk of session cookie being stolen or credentials being intercepted in transit. 

- I configured ingress rule for the application node security group to allow ingress only from the ALB. Currently with node security group rules, any pod on the application node is exposed to the alb ingress traffic that is intended for just the web application. I mitigated that risk with the network policy that restricts ingress on port 80 to only the web application(dvwa). In a production environment, I could implement VPC CNI prefix delegation to have sufficient ENI to implement pod level security group.

- I configured the application, observability and isolated node security groups to restrict egress to only port 443. By routing traffic through the NAT gateway, it ensures that only outbound traffic initiating from the subnets is allowed

**[VPC Endpoints](terraform/modules/network/endpoints.tf)**
  
- I provisioned eight interface endpoints and one S3 gateway endpoint. With VPC endpoints, traffic stays entirely on AWS's private network and never touches the public internet, this eliminates the risk of intercepting API calls carrying credentials or sensitive metadata. My original intent was to place the endpoints only in the isolated subnet due to high sensitive vault and database pods in the node, but I discovered that once you create an interface endpoint with private DNS enabled, AWS automatically configures Route 53 Resolver rules that rewrite the service hostname for the entire VPC, not just the subnet the endpoint lives in. This means all nodes across every tier resolve to the enabled endpoint's private IP regardless of having a route to NAT Gateway, so I configured the endpoint security groups to allow traffic from both the private and isolated tiers.

- I configured the KMS endpoint to have its own dedicated security group restricted to the isolated tier only. Since private DNS makes the KMS endpoint reachable from all tiers by default, scoping the security group to isolated tier ensures that only Vault's auto-unseal calls can actually reach it. 


**Application Load Balancer and Web Application Firewall**

- The ALB Controller in the private subnet because it's a Kubernetes controller that watches for Ingress resources, makes AWS API calls to provision and configure ALBs, and requires a privileged IRSA. Putting it in the public subnet where it is directly reached from the internet would expose the pod with its extensive privileges closer to the public network. If the pod is compromised, the attacker has an IRSA that can manipulate load balancers. Also, by keeping it in the private subnet, it reaches the AWS APIs through secure, internal VPC endpoints.

- DVWA is a deliberately vulnerable application with known vulnerabilities like SQL Injection and XSS. I implemented [WAF managed rule groups](terraform/modules/security/waf.tf) to mitigate these vulnerabilities.
  
- The SQL Database managed rule group blocks known SQL injection patterns at the ALB edge before the request reaches the application. Also, the Common Threats managed rule group catches known XSS patterns in request parameters, headers, and body. Both rule groups are maintained by AWS and updated automatically as new attack patterns are published.
 
- Inasmuch as AWS Shield is automatically enabled, I also implemented WAF rate limiting at 100 requests per minute per IP to throttle HTTP flood attacks and automated brute force tools like credential stuffing. Shield Standard operates at the network layer and absorbs volumetric attacks at the AWS edge like SYN floods and UDP amplification. It does not have visibility into HTTP request content. A flood of HTTP GET requests can pass through Shield because each individual TCP connection is valid.

- With CloudWatch metrics and sampled requests enabled, WAF will store a sample of the requests that matched each rule in the WAF console, and will provide visibility into the actual request content for investigation. In a production environment, I can combine this with full WAF logging to Kinesis Firehose to capture all requests.

- I configured the [ALB](k8s/dvwa/ingress.yaml) to terminate TLS using a certificate I generated with cert-manager and imported into ACM, with ALB security policy enforcing TLS 1.3 only at the connection level. This eliminates known weaknesses like CBC mode ciphers vulnerabilities that can be seen with TLS 1.2 or lower versions. TLS 1.3 also has a faster handshake and provides forward secrecy by default on every connection. In a production environment with a registered domain, I would configure ACM to provision and automatically renew a publicly trusted ALB certificate for the domain.

- I stripped the ALB response header to enforce the security principle of Reconnaissance defense through Information Obscurity. DVWA is a pre-built image that I do not control, I would need to either configure the server inside the DVWA image to suppress the header, which requires rebuilding the image, or configure a response transformation at the third-party ingress controller level like envoy or NGINX.

---

## EKS Cluster, OIDC and Node Management

**[Cluster Configuration](terraform/modules/eks/main.tf)**
  
- I provisioned the EKS cluster with both public and private API endpoint access. I enabled public access to be able to manage the cluster from my VM. In a production environment, it should be Private-only access with a bastion or VPN to run kubectl.

- I enabled control plane logging for the api, audit, and authenticator log types. The api and audit logs capture who accessed the cluster and what they did, and the authenticator captures IAM-to-Kubernetes identity mapping, this gives visibility into how AWS identities are being used to authenticate into the cluster. These logs stream natively into Amazon CloudWatch for real-time monitoring and investigation.

**Node Group IAM Roles**
  
- I created separate IAM roles for each node group: apps, isolated, and observability. The isolated node runs Vault which needs access to KMS endpoint which the other nodes do not need. By separating the roles, I can contain the blast radius to only what each node legitimately needs.

- In a high availability production environment, this separation will also enable targeted incident response. If the apps node is compromised, I can revoke its IAM role immediately without touching the isolated or observability node groups.

**IMDSv2 Enforcement**
  
- I enforced IMDSv2 on the nodes launch templates with a hop limit of 1. The Instance Metadata Service returns the node's IAM role credentials to any caller. With IMDSv1, an attacker can exploit an SSRF vulnerability in DVWA which is intentionally vulnerable to make the server issue an HTTP GET to the metadata endpoint and steal the node's AWS credentials with no authentication. IMDSv2 will prevent this because it requires a PUT request to obtain a session token first. Also, with a hop limit of 1, a compromised pod cannot get a return traffic from the IMDS.

**etcd Encryption**
  
- I enabled envelope encryption for Kubernetes Secrets using a dedicated KMS customer managed key. etcd holds the complete cluster state including Secrets, ConfigMaps, pod specs, service account definitions, RBAC policies, network policies, and deployment configurations. An attacker who gains access to an unencrypted etcd snapshot has a complete blueprint of my infrastructure. By default, EKS encrypts the underlying etcd EBS volume at the AWS level, but every object is stored in plaintext. With envelope encryption, every Kubernetes secret object will be additionally encrypted with my CMK before being written to disk. Hence, an attacker who gains access to an etcd snapshot or backup will not be able to read Secret values without also compromising the KMS key.

**OIDC and IRSA**
  
- I configured an OIDC provider for the EKS cluster and created [IRSA roles](terraform/modules/eks/irsa.tf) for the EBS CSI driver and Vault. IRSA eliminates the need for any static AWS credentials inside pods. It also gives each workload its own distinct AWS identity so that compromising one pod does not grant the attacker the permissions of any other pod on the same node. I configured three conditions for each role trust policy: the OIDC sub claim to restrict which specific Kubernetes service account can assume the role, the aud claim to ensure the token is intended for AWS STS specifically, and an aws:SourceVpce condition to restrict role assumption to requests arriving through the cluster's own STS VPC endpoint to prevent a stolen token to be used from outside the cluster.

---

## Patch Management, SSM Session Logging, and ECR Hardening

 **[SSM Patch Management](terraform/modules/eks/patching.tf)**
 
- I configured SSM Patch Manager with a patch baseline for Amazon Linux 2023 nodes, a weekly maintenance window, and a Scan-only operation. I used Scan rather than Install for optimised EKS AMIs. This replaces the AMI as a whole rather than patching in place; installing packages live on a running node risks drifting away from the tested AMI configuration. The Scan operation will provide visibility on when a node's AMI is outdated. I configured the launch templates to tag instances with the Patch Group tag so the maintenance window will correctly target the right instances.

- At the CI/CD stage, I will configure EventBridge rule which will be triggered by the SSM patch compliance findings to invoke a lambda weebhook forwarder to the CI/CD pipeline. This way, EKS can safely perform the draining, cordoning, and replacing nodes sequentially.


**[SSM Session Manager](terraform/modules/security/ssm_logging.tf)**
  
- I configured SSM Session Manager as the only administrative access path to nodes. To enforce strict access controls, I implemented IAM policies targeting both interactive sessions and remote scripts: connections are restricted to instances tagged with the correct environment value, and remote executions are strictly limited to two approved SSM Run Command documents (AWS-RunPatchBaseline and AWS-RunShellScript). For a production enviironment, I would also enforce a conditional deny statement to block sessions where MFA is false.

- I configured the session activity to log to CloudWatch Logs for capturing an active session in real time, and S3 for post session transcripts. I enabled CloudWatch because S3 only writes the complete transcript after a session ends, if an attacker starts a session and it is terminated abruptly, the in-progress output would be lost. CloudWatch streams continuously, so partial output will be captured before the session closes.

- I set runAsEnabled to false in the Session Manager preferences. In a production environment I would enable this and configure runAsDefaultUser to a dedicated non-root user, so that every session is tied to a named identity for audit logging.

**[ECR Hardening](terraform/modules/eks/ecr.tf)**

- I used a private ECR repository for DVWA because it serves as my custom application image which should never be stored in a public registry where it is exposed to the internet and accessible to anyone. I enabled image tag immutability to prevent existing tags from being overwritten which protects against an attacker replaces a trusted image tag with a malicious one.

- I enabled scan on push so every new image is automatically scanned for OS and dependency vulnerabilities before it can be pulled by the cluster. I restricted pull access to the apps node IAM role only so no other principal can pull the image and configured cross-account deny to prevent any identity outside this AWS account from accessing the repository.

- I configured a pull-through cache rule for Docker Hub upstream because these images are from trusted open-source charts that I do not need to modify. The pull-through cache proxies requests through ECR automatically, eliminating the internet dependency and Docker Hub rate limiting. I stored the Docker Hub credentials in Secrets Manager and referenced them in the cache rule to keep registry credentials out of Terraform state and version control.
    
---

## AWS Logging, Monitoring, and Detection 

**CloudTrail**
  
- I configured [cloudtrail](terraform/modules/security/cloudtrail.tf) logging to a dedicated s3 bucket with a customer managed KMS key to provide an audit trail of every API call made. The KMS key grants decrypt permission only to the account root, an attacker who compromises S3 cannot be able to read the logs without also compromising the key. 

- I enabled object lock to prevent the log files from being deleted during the retention period. I chose GOVERNANCE over COMPLIANCE mode, and a 30 days retention period because this is an active development environment and COMPLIANCE mode would make it impossible to destroy since even root cannot override it. In production, I would use COMPLIANCE mode and a longer retention period (as well as Glacier for archiving to cut storage cost significantly) to prevent anyone including root to delete or modify a log file during the retention period. This will prevent an attacker from covering up or deleting their trails.
   
- Because WORM doesn’t protect from tampering while on transit, I also enabled log file validation to create a cryptographic hash of every file which detects if the file was modified before reaching the bucket. 

- I also scoped the bucket policy to my specific trail to prevent denial of service through storage exhaustion, or a malicious attacker hiding their activities by polluting the logs.

*NOTE* I created one dedicated [KMS key](terraform/modules/security/kms.tf) per service throughout this project, this limits the blast radius because a compromise of one key will only expose that service's data.

**VPC Flow Logs**
  
- I enabled [VPC Flow Logs](terraform/modules/security/flowlog.tf) writing to S3. Flow logs capture metadata about every network connection in the VPC. This provides evidence for when a breach or suspicious activity occurs including what communicated with what, when, and how much data moved. Also, compliance frameworks like PCI-DSS and ISO 27001 require demonstrable network monitoring and the ability to reconstruct network activity during an incident. I chose S3 over CloudWatch for cost management. I also enabled guard duty which consumes flow flog and forwards critical findings to SecurityHub for visualization.

**[GuardDuty](terraform/modules/security/guardduty.tf)**
  
- I configured guardduty for account wide threat detection through CloudTrail API call logs, VPC Flow Logs, and DNS query logs. I chose RUNTIME MONITORING alonside EKS ADDON MANAGEMENT and EC2 AGENT MANAGEMENT over EKS RUNTIME MONITORING because EKS Runtime Monitoring only monitors threats within the Kubernetes layer. Runtime Monitoring covers both the container layer AND the underlying EC2 host, making it able to detect threats that have already escaped the container boundary and are executing directly on the node OS.

- I enabled EKS AUDIT LOGS to provide visibility into events at the Kubernetes control plane like privilege escalations, suspicious exec commands, or abnormal API call patterns from service accounts.

- I also enabled S3 DATA EVENTS to detect unauthorized access or exfiltration of sensitive data from my S3 buckets, EBS MALWARE PROTECTION to scan volumes attached to the EKS nodes for malware that could persist across container restarts, and Lambda network activity monitoring to detect anomalous outbound connections from the Lambda remediation functions that could indicate a compromised function making unauthorized calls.

- I configured GuardDuty to publish findings every 6 hours to reduce the frequency of CloudWatch metric updates and S3 writes for cost management. In a production environment, I would reduce this to 15 minutes so that active threats are surfaced and responded to before an attacker has time to establish persistence or move laterally.

  
**[AWS Config](terraform/modules/security/config.tf)**

- I also enabled AWS config to detect misconfigurations for auto-remediation through lambda or alerting through [sns alert](terraform/modules/security/sns.tf) to maintain the required security posture. 

- My config rules monitor for when ssh port, database, and vault sensitive ports are configured open and auto-remedates through its [Lambda function](lambda/remediate_security_group/handler.py) to protect from accidental or deliberate exposure. It also monitors and alerts when EBS encryption is disabled for human intervention.

- For the S3 account-level Block Public Access remediation, I used an SSM Automation document (AWSConfigRemediation-ConfigureS3PublicAccessBlock) rather than a Lambda function. The removes the maintenance burden because AWS owns and maintains that SSM document.
  
- I created a dedicated KMS customer-managed key for the Config S3 bucket rather than reusing the CloudTrail key or any other existing key. The is to contain blast radius in a case of compromise.

**[Security Hub](terraform/modules/security/securityhub.tf)**
  
- I linked Config and Guardduty to Security Hub to have a centralized dashboard for the security findings for easy monitoring. I configured the Security Control mode which consolidates controls so that the same underlying check only produces one finding regardless of how many standards reference it which reduces noise.

---

## EventBridge and Lambda Automated Remediation

- I configured lambda functions for auto-remediation of critical threats or misconfigurations when triggered through [EventBridge](terraform/modules/security/eventbridge.tf) by Guardduty findings or Config.
  
- I configured each Lambda function with its own [IAM role](terraform/modules/security/lambda.tf) with only the permissions it needs. This follows the principle of least privilege and prevents an attacker who exploits a vulnerability in one function from exploiting others.

- I used inline zip files for the lambda codes which are deployed through terraform on the fly because they are small single-file Python scripts. It also makes version control easier. I could use an S3 deployment in a production environment with large deployment packages that need to be shared across multiple functions or accounts, or when there is a need for separate lifecycle management for the code.

- The CloudTrail Config rule evaluates and fires when any trail is NON-COMPLIANT but I configured the [remediation handler](lambda/remediate_cloudtrail/handler.py) to only auto-remediate the main trail. This is because there are justifications why a trail may need to be discontinued and enforcing autoremediation on all trails is not the right call. I enforced it on the main trail because it captures core security information and should never be disabled. The config evaluates on all trails for visibility but only triggers autoremediation on the main trail.

- I configured the instance credential exfiltration remediation to send sns alert instead of revoking the node role. This is because this is a dev environment and there’s no high availability. Revoking the node role will cause every pod on that node to lose access to AWS, causing denial of service. In a production environment with high availability, I should configure it to revoke the node role.

- Similarly, I configured the GuardDuty findings that indicate node compromise such as "Trojan:EC2/DNSDataExfiltration", "Trojan:EC2/DGADomainRequest.B", "Impact:EC2/BitcoinDomainRequest.Reputation", and "Impact:EC2/MaliciousDomainRequest.Reputation" to send sns alert instead of isolating the node. In a production environment, with high availability, these alerts would require isolating the node automatically.

- I configured the compromised credential finding to be auto-remediated by applying a deny policy to the IAM role or deactivating the access key. This is because for that threat to be flagged, AWS's threat intelligence has already made the determination with high confidence. Requiring human review before remediating widens the window between detection and containment, and this leaves the credentials active giving the attacker time to create new credentials, escalate privileges, or exfiltrate data. The [lambda function](lambda/revoke_iam_session/handler.py) denies the specific session or deactivates the specific key, so the blast radius is contained.

---

## Observability and Monitoring

**[Kube-Prometheus-Stack](k8s/observability/kube-prometheus-values.yaml)**

- In the observability node, I deployed Prometheus and Grafana for metrics collection and dashboard visualization.

- I configured a [ServiceMonitor](k8s/database/servicemonitor.yaml) for MariaDB to collect application specific metrics: slow queries, active connection counts, and buffer pool utilisation, through the mysqld-exporter sidecar. These metrics will reveal database problems before they surface as application errors for early intervention. 

 ![metrics](screenshots/phase2/exporter.png)
 
 *database metrics collection*
 
- DVWA is a plain PHP application and exposes no metrics endpoint, so a ServiceMonitor is not applicable. So, I configured a [PrometheusRule](k8s/dvwa/prometheus-rule.yaml) that evaluates metrics cAdvisor already collects automatically from the node for every running container.

- I didn't measure CPU against a full core because it would give a misleading percentage; I divided actual CPU usage by the CPU limit configured for the container to get a true saturation figure. The rule will fire a critical alert when DVWA reaches 80% of its allocated CPU for more than two minutes, providing early detection before the pod becomes unresponsive.

- This covers both operational overload and a potential denial of service attempt against the vulnerable application. In a production environment, I would also configure a Horizontal Pod Autoscaler to automatically scale a new DVWA pod before the existing one becomes saturated, so that the cluster can absorb the load while the alert is being investigated.

- I configured severity-based AlertManager routing to forward only critical alerts to an SNS topic using an IRSA-scoped role ARN. While Warning and info alerts will remain in Grafana for visibility. 

- In a production environment, I would also route AlertManager Watchdog to a dead man's switch service like PagerDuty to alert when AlertManager alert stops firing.

- For Grafana authentication, I configured grafana to sync the admin credentials through an [ExternalSecret](k8s/observability/observability-external-secret.yaml) synced from Vault by ESO. This way, the Grafana admin password is managed by Vault's access control, audited through Vault's audit log, and rotated without touching the Kubernetes cluster directly.

- In a production environment, I can also utilize Grafana's built in RBAC for restricting dashboard and datasource access per authenticated user. This will restrict which teams can query which namespaces in Loki and which metrics in Prometheus.
In this project, I used port forwarding to access the dashboard, I could also also enforce TLS 1.3 on grafana connections through the ALB, and also restrict the security group ingress from the security team ipcidr block


**Loki** 

- I deployed [Loki](k8s/observability/loki-values.yaml) in Simple Scalable mode, which splits the monolithic Loki binary into separate write, read, and backend components with each running independently and scalable on its own. This will provide the operational flexibility to scale write throughput independently from query performance in cases when log ingestion spikes during a security incident without necessarily increasing query load.

- I configured [IRSA](terraform/modules/eks/irsa.tf) and an [S3 bucket](terraform/modules/security/loki_s3.tf) with KMS encryption for long-term log storage of Loki logs. This IRSA ensures that only Loki with its service account in the observability namespace can write to the S3 bucket. I also included a source VPC condition to ensure that the role can only be assumed from inside the VPC. This protects against an attacker exfiltrating or maliciously corrupting Loki storage from outside the cluster.

- The KMS key policy also ensures that S3 can only encrypt data for Loki's IRSA principal, even if an attacker obtained a different IAM identity, they cannot write to or read the encrypted log data because the KMS key will refuse to generate or decrypt data keys for any identity other than Loki's role.

- I also referenced the SSE-KMS encryption type explicitly in the Loki values file using sse_config pointing to the KMS key ARN. This ensures Loki will fail to write to the S3 bucket if KMS encryption is ever disabled or misconfigured on the bucket and not silently falling back to unencrypted writes. This will protect against a misconfiguration or a deliberate attempt to disable encryption going undetected while logs continue to accumulate without protection.

- **publishNotReadyAddresses**: When I first deployed Loki, the read component was stuck in Pending and never became ready. This is because Loki uses memberlist gossip protocol to form a ring where each component knows about every other component in the cluster. A new Loki component at start up, needs to join the ring before the readiness probe can detect it as ready. Kubernetes, by default, only publishes the IP addresses of pods that are ready to the memberlist service.I enabled publishNotReadyAddresses: true on the memberlist service so that Kubernetes can publish the pod's IP address in the service endpoints even before the pod passes its readiness probe.  

- I disabled Loki canary because this is a development environment where I am already verifying log ingestion manually through Grafana and Falco alert correlation, the canary adds resource consumption and log noise. In a production environment where automated SLA monitoring is required, I would enable it to continuously validate the log pipeline end-to-end and alert when log delivery latency exceeds the acceptable thresholds.
  
**[Grafana Alloy](k8s/observability/alloy-values.yaml)**

- For Alloy to function as a log shipper, it needs access to /var/log which is a host-mounted path on the node filesystem. It needs this access to read pod log files directly from disk which captures crash logs from pods that have already died. The default Helm chart also gives Alloy cluster-wide RBAC permissions including read access to Secrets across all namespaces. An attacker who compromises the Alloy container and steals its automatically mounted service account token can use that token directly against the Kubernetes API, bypassing Alloy's config language entirely, and can read every Secret in every namespace. Because Kubernetes Secrets are only base64 encoded, not encrypted at the API level, the credentials will be readable.

- I scoped down these permissions so that even with a stolen token, access is limited to pod metadata, namespaces, and node information. 

---

## Branch Protection, AWS OIDC, and Workflow IAM Roles

**Module Separation**

- I separated the Terraform root modules into three modules: network, eks, and security for independent management with its own state file and GitHub Actions workflows. This will prevent a misconfiguration or a compromised workflow in one from affecting the others. I used Terragrunt to manage the dependencies between them.
  
**[AWS OIDC](terraform/cicd/main.tf)**

- I configured AWS OIDC federation for GitHub Actions roles so that to prevent exposing AWS credentials anywhere. 

- I created six IAM roles: one plan role and one apply role for each of the three workflows to enforce least privilege. I also locked each role to its specific workflow file through the OIDC trust condition. The plan roles have read-only access while the apply roles will have the permissions needed to create and modify resources in its module. This will prevent compromise of a plan role being used to destroy or modify infrastructure.

- I also configured the apply roles with an additional constraint; they can only be assumed from the main branch. This will prevent apply role from running from a feature branch so that infrastructure changes must go through the pull request review process and be merged to main before any apply can happen.

- Currently, the apply roles have Administrator Access. This is because predicting the exact IAM permissions a Terraform workflow needs before running is impractical. I intend to harden this after the first full apply by using IAM Access Analyzer to analyse the CloudTrail logs generated during the apply and generate a least-privilege policy based on what each role actually called. This follows the principle of least privilege and reduces blast radius if a role is compromised.
  
- In a production environment I would perform this analysis in a staging environment first, validate that the streamlined permissions do not break any workflow, and then apply the scoped policies to production.

**[Branch and Environment Protection](terraform/cicd/environment.tf)**

- I configured branch protection on main to require pull request reviews before merge. I also configured environment protection on the production environment so that apply jobs will require a manual approval gate before running. This will provide a final checkpoint before infrastructure changes are applied.



