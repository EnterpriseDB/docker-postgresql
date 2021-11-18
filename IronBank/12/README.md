# Cloud Native Postgres

## Cloud Native PostgreSQL by EnterpriseDB

**PostgreSQL Operator for mission critical databases in OpenShift Container Platform**

---

Cloud Native PostgreSQL is a stack designed by EnterpriseDB to manage PostgreSQL
workloads particularly optimized for Private Cloud environments with Local 
Persistent Volumes (PV). PostgreSQL 10 or higher versions are supported.

## Features & Benefits

**Self-Healing**:
Self-Healing capability through automated failover of the primary instance
(by promoting the most aligned replica) and automated recreation of a replica

**Switchover**:
Planned switchover of the primary instance, by promoting a selected replica

**Scaling**:
Scale up/down capabilities, including integration with `kubectl scale`

**Rolling updates**:
Rolling updates for PostgreSQL minor versions and operator upgrades

**Local Persistent Volumes**:
Support for Local Persistent Volumes with PVC templates and storage classes

**Reuse of Persistent Volumes**:
Reuse of Persistent Volumes storage in Pods

**Secure connections**:
TLS connections and client certificate authentication.

**Backup and Recovery**:
Continuous backup to an S3 compatible object store and full recovery from an S3 compatible object store backup.
Replica clusters for PostgreSQL deployments across multiple Kubernetes clusters, enabling private, public, hybrid, and multi-cloud architectures

**Logging**:
Native customizable exporter of user defined metrics for Prometheus through the metrics port (9187)
Standard output logging of PostgreSQL error messages in JSON format

**Security**:
Support for the restricted security context constraint (SCC) in Red Hat OpenShift
The following guidelines and frameworks have been taken into account for container-level security:
 - [https://dl.dod.cyber.mil/wp-content/uploads/devsecops/pdf/DevSecOps_Enterprise_Container_Image_Creation_and_Deployment_Guide_2.6-Public-Release.pdf](Container Image Creation and Deployment Guide), developed by the Defense Information Systems Agency (DISA) of the United States Department of Defense (DoD)
 - [https://www.cisecurity.org/benchmark/docker/](CIS Benchmark for Docker), developed by the Center for Internet Security (CIS)
