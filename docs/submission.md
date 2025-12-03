# Puppies Social Media API - Backend Implementation Plan

**Author:** Roberto  
**Date:** December 2025  
**Repository:** https://github.com/robcarmo/puppies-api

---

## Overview

This document presents a comprehensive implementation plan for the backend of a puppy-focused social platform supporting posts, likes, comments, and follows. The system is designed to be scalable, reliable, secure, and easy to evolve while remaining cost-effective.

> **Note:** The complete code implementation draft is available at:  
> **https://github.com/robcarmo/puppies-api**

---

## 1. High-Level Architecture

### Core Design Principles

To support a global user base with viral traffic spikes, the system follows a **microservices-based, event-driven architecture**. This ensures:

- **Scalability:** Independent scaling of read/write paths and domain services.
- **Reliability:** Failure isolation and asynchronous processing for heavy tasks.
- **Evolvability:** Clear boundaries allowing teams to iterate on services (e.g., Feed, Users) independently.

### System Components

The architecture is composed of the following key layers:

#### 1. Edge Layer (API Gateway & CDN)

-   **CDN (CloudFront/Cloud CDN):** Caches static assets (images/videos) and terminates TLS close to the user.
-   **API Gateway / Load Balancer:** Handles rate limiting, WAF protection, and routes traffic to internal services. It offloads cross-cutting concerns like auth verification and SSL termination.

#### 2. Service Layer (Kubernetes)

-   **API Service (BFF):** Stateless REST API handling request validation, orchestration, and response shaping.
-   **Domain Services:**
    -   `UserService`: Profiles, auth, follow relationships.
    -   `PostService`: Content creation, media metadata.
    -   `InteractionService`: Likes, comments.
    -   `FeedService`: Personalized timeline generation (complex read logic).
-   **Background Workers:** Async consumers for feed fan-out, notifications, and analytics.

#### 3. Data Layer

-   **Primary DB (PostgreSQL):** System of record. Chosen for relational integrity (FKs), rich query capability, and reliability.
-   **Cache (Redis):** Low-latency access for user sessions, rate limits, and pre-computed feeds.
-   **Object Storage (S3/GCS):** Durable storage for user-uploaded media.

#### 4. Messaging (Kafka)

-   Acts as the backbone for eventual consistency. Decouples write-heavy operations (e.g., "User A posted") from read-heavy side effects (e.g., "Update User B's feed").

### Architecture Diagram

![Architecture Diagram](./architecture-diagram.png)

The diagram illustrates the complete system architecture with clear separation of concerns across edge, service, data, and messaging layers.

---

## 2. Data Model & Storage Strategy

### Schema Design

We use a relational model to enforce integrity, particularly for social graph data.

-   **Users:** `id, username, email, password_hash, created_at`
-   **Posts:** `id, user_id, content, media_url, media_type, created_at`
    -   *Index:* `(user_id, created_at DESC)` for fast author profile feeds.
-   **Follows:** `follower_id, followee_id, created_at` (Composite PK)
    -   *Index:* Both columns indexed for bidirectional graph traversal.
-   **Likes:** `user_id, post_id, created_at` (Composite PK)
-   **FeedEntries:** `user_id (owner), post_id, created_at`
    -   *Optimization:* This table is a "materialized view" of a user's timeline, populated asynchronously.

### Handling Scale & Hotspots

#### 1. The "Influencer" Problem

A user with 1M followers would trigger 1M writes on every post (Fan-out on Write).

**Solution: Hybrid Approach**

-   **Standard Users (<10k followers):** Push model. Workers insert `FeedEntry` for all followers. Fast reads.
-   **VIPs (>10k followers):** Pull model. Do not fan-out. When a user requests their feed, we fetch VIP posts dynamically and merge them with the pre-computed feed.

#### 2. Viral Content

High concurrency on a single row (e.g., counting likes).

**Solution:** Buffer likes in Redis and flush to DB in batches, or use approximate counters for display and eventual consistency for storage.

---

## 3. API Surface & Security

### API Design (REST)

We expose a versioned REST API (`/v1/`) documented via OpenAPI 3.0.

**Key Endpoints:**

-   `POST /v1/posts`: Create post (returns presigned upload URL for media).
-   `GET /v1/feed`: Retrieve personalized feed (cursor-based pagination).
-   `POST /v1/posts/{id}/likes`: Idempotent like action.
-   `POST /v1/users/{id}/follow`: Follow a user.
-   `GET /v1/users/{id}/posts`: User timeline.

### Security & Authentication

-   **Authentication:** OAuth2/OIDC (Google/Apple) + JWT Access Tokens (15 min TTL).
-   **Authorization:** Role-Based Access Control (RBAC) enforced at the API layer.
-   **Rate Limiting:** Token bucket algorithm in Redis.
    -   *Global:* 1000 req/min per IP.
    -   *Sensitive:* 10 req/min for `POST /posts` to prevent spam.

### Security Measures

-   **Input Validation:** Pydantic models for request validation
-   **SQL Injection Prevention:** Parameterized queries via ORM (SQLAlchemy)
-   **CORS:** Whitelist trusted origins
-   **Content Moderation:** ML-based filtering (GCP Vision API)
-   **Encryption:** TLS 1.3 in transit; AES-256 at rest

---

## 4. Platform & Infrastructure

### Technology Choices

-   **Compute:** **Kubernetes (GKE)**. Provides standard orchestration for both API services and background workers, with Horizontal Pod Autoscaling (HPA) based on CPU/Memory and custom metrics (Kafka lag).
-   **Database:** **Managed PostgreSQL (Cloud SQL)**. Reduces operational overhead (backups, patching). We enable Multi-AZ for HA and Read Replicas for scaling `GET` traffic.
-   **Messaging:** **Managed Kafka (Confluent Cloud)**. Essential for durability and high-throughput event streaming.
-   **IaC:** **Terraform**. All infrastructure is defined as code to ensure reproducibility across Dev, Staging, and Prod environments.

### Cost Management

-   **Spot Instances:** Use Preemptible nodes for stateless background workers (tolerant to interruption), saving ~70% on compute.
-   **Storage Tiering:** Lifecycle policies on GCS to move old media to Nearline/Coldline storage after 30 days.
-   **Auto-scaling:** Aggressive scale-down policies during off-peak hours.
-   **CDN Optimization:** Cache-Control headers (1 year for immutable media), compression (Brotli/gzip).

### Infrastructure as Code Example

```hcl
module "gke" {
  source     = "./modules/gke"
  project_id = var.project_id
  region     = var.region
  network    = module.vpc.network_name
  subnetwork = module.vpc.subnetwork_name
}

module "cloudsql" {
  source     = "./modules/cloudsql"
  project_id = var.project_id
  region     = var.region
  network    = module.vpc.network_self_link
}
```

---

## 5. Delivery & Operations

### CI/CD Pipeline

1.  **CI:** On PR, run unit tests, linting, and SAST (SonarQube). Build Docker images.
2.  **CD (Staging):** Deploy to staging namespace. Run integration tests and lightweight load tests.
3.  **CD (Production):** Canary deployment. Route 5% of traffic to new version. Monitor error rates and latency. If healthy, roll out to 100%.

### Observability

**Metrics (Prometheus/Grafana):**

-   *RED Method:* Rate, Errors, Duration for all HTTP endpoints.
-   *Business Metrics:* Posts per minute, Active Users, Feed Latency.

**Tracing (OpenTelemetry):** End-to-end tracing to identify bottlenecks (e.g., "Why is the feed slow? Is it the DB or Redis?").

**Logs (ELK/Loki):** Structured JSON logs with `trace_id` for correlation.

### Key Metrics and SLOs

| Metric              | SLI                         | SLO                              |
|---------------------|-----------------------------|---------------------------------|
| Feed latency        | p99 response time           | < 500ms for 99.9% of requests   |
| API availability    | Success rate (non-5xx)      | > 99.9% uptime                  |
| Post creation       | p95 response time           | < 300ms                         |
| Cache hit ratio     | Redis hits / total requests | > 80% for feed endpoint         |

### Reliability & Recovery

**Circuit Breakers:** Implemented in the API client. If the `FeedService` fails, fallback to a cached "popular posts" list rather than 500 error.

**Disaster Recovery:**

-   **RPO:** < 5 min (Async replication to standby region).
-   **RTO:** < 1 hour (Automated failover scripts).
-   **Backups:** Daily DB snapshots + Continuous WAL archiving.

### Operational Scenarios

**Scenario: API Latency Spike**

1.  **Alert:** PagerDuty triggers on "P99 Latency > 500ms".
2.  **Diagnose:** Check Grafana. If DB CPU is high, check `pg_stat_statements` for slow queries.
3.  **Remediate:** If a specific query is the culprit, add an index or temporarily enable aggressive caching. If load is general, scale up read replicas.

**Graceful Degradation:**

-   Feed service down: Serve cached feeds (stale up to 15 min)
-   DB overload: Reduce feed page size (100 → 20 posts)
-   Notification service down: Queue notifications for retry

---

## Implementation Details

### Project Structure

The complete implementation is available at **https://github.com/robcarmo/puppies-api** and includes:

```
puppies-api/
├── app/
│   ├── api/v1/          # API endpoints and routers
│   ├── core/            # Configuration and database setup
│   ├── domain/          # Business logic and database models
│   │   ├── users/       # User and Follow models
│   │   ├── posts/       # Post models
│   │   ├── interactions/ # Like and Comment models
│   │   └── feed/        # Feed generation logic
│   └── schemas/         # Pydantic models for validation
├── terraform/           # Infrastructure as Code (GCP)
│   └── modules/         # VPC, GKE, CloudSQL, Memorystore
├── docker-compose.yml   # Local development environment
└── Dockerfile          # Container image definition
```

### Technology Stack

-   **Language:** Python 3.9+
-   **Framework:** FastAPI
-   **ORM:** SQLAlchemy
-   **Validation:** Pydantic
-   **Database:** PostgreSQL 14
-   **Cache:** Redis 7
-   **Messaging:** Kafka
-   **Container:** Docker
-   **Orchestration:** Kubernetes (GKE)

### Running Locally

```bash
# Start all services
docker-compose up -d

# Access API documentation
open http://localhost:8000/docs
```

---

## Conclusion

This architecture balances scalability, reliability, security, and cost-effectiveness for a puppy-focused social platform. Key design decisions include:

-   **Hybrid feed model** to handle influencer hotspots
-   **Event-driven architecture** for decoupling and resilience
-   **Cloud-native design** with specific GCP service recommendations
-   **Comprehensive observability** with SLOs, dashboards, and alerting
-   **Robust CI/CD** with automated testing, security scanning, and safe deployments
-   **Cost optimization** through preemptible instances, tiered storage, and right-sizing

The system is designed to evolve: microservices enable independent scaling, versioned APIs allow backward-compatible changes, and IaC ensures reproducible environments. With proper monitoring and incident response procedures, the platform can maintain high availability while adapting to growing user demands.

---

**For the complete code implementation, please visit:**  
**https://github.com/robcarmo/puppies-api**
