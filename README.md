# Puppies Social Media API

## Overview
This repository contains the backend implementation and architectural documentation for the Puppies Social Media API.

## 1. High-Level Architecture

### Core Design Principles
To support a global user base with viral traffic spikes, the system follows a **microservices-based, event-driven architecture**. This ensures:
- **Scalability:** Independent scaling of read/write paths and domain services.
- **Reliability:** Failure isolation and asynchronous processing for heavy tasks.
- **Evolvability:** Clear boundaries allowing teams to iterate on services (e.g., Feed, Users) independently.

### System Components
The architecture is composed of the following key layers:

1.  **Edge Layer (API Gateway & CDN):**
    -   **CDN (CloudFront/Cloud CDN):** Caches static assets (images/videos) and terminates TLS close to the user.
    -   **API Gateway / Load Balancer:** Handles rate limiting, WAF protection, and routes traffic to internal services. It offloads cross-cutting concerns like auth verification and SSL termination.

2.  **Service Layer (Kubernetes):**
    -   **API Service (BFF):** Stateless REST API handling request validation, orchestration, and response shaping.
    -   **Domain Services:**
        -   `UserService`: Profiles, auth, follow relationships.
        -   `PostService`: Content creation, media metadata.
        -   `InteractionService`: Likes, comments.
        -   `FeedService`: Personalized timeline generation (complex read logic).
    -   **Background Workers:** Async consumers for feed fan-out, notifications, and analytics.

3.  **Data Layer:**
    -   **Primary DB (PostgreSQL):** System of record. Chosen for relational integrity (FKs), rich query capability, and reliability.
    -   **Cache (Redis):** Low-latency access for user sessions, rate limits, and pre-computed feeds.
    -   **Object Storage (S3/GCS):** Durable storage for user-uploaded media.

4.  **Messaging (Kafka):**
    -   Acts as the backbone for eventual consistency. Decouples write-heavy operations (e.g., "User A posted") from read-heavy side effects (e.g., "Update User B's feed").

### Architecture Diagram

![Architecture Diagram](./docs/architecture-diagram.png)

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
1.  **The "Influencer" Problem:** A user with 1M followers would trigger 1M writes on every post (Fan-out on Write).
    -   **Solution:** Hybrid Approach.
        -   **Standard Users (<10k followers):** Push model. Workers insert `FeedEntry` for all followers. Fast reads.
        -   **VIPs (>10k followers):** Pull model. Do not fan-out. When a user requests their feed, we fetch VIP posts dynamically and merge them with the pre-computed feed.
2.  **Viral Content:** High concurrency on a single row (e.g., counting likes).
    -   **Solution:** Buffer likes in Redis and flush to DB in batches, or use approximate counters for display and eventual consistency for storage.

---

## 3. API Surface & Security

### API Design (REST)
We expose a versioned REST API (`/v1/`) documented via OpenAPI 3.0.

-   `POST /v1/posts`: Create post (returns presigned upload URL for media).
-   `GET /v1/feed`: Retrieve personalized feed (cursor-based pagination).
-   `POST /v1/posts/{id}/likes`: Idempotent like action.

### Security & Auth
-   **Authentication:** OAuth2/OIDC (Google/Apple) + JWT Access Tokens (15 min TTL).
-   **Authorization:** Role-Based Access Control (RBAC) enforced at the API layer.
-   **Rate Limiting:** Token bucket algorithm in Redis.
    -   *Global:* 1000 req/min per IP.
    -   *Sensitive:* 10 req/min for `POST /posts` to prevent spam.

---

## 4. Platform & Infrastructure

### Technology Choices
-   **Compute:** **Kubernetes (EKS/GKE)**. Provides standard orchestration for both API services and background workers, with Horizontal Pod Autoscaling (HPA) based on CPU/Memory and custom metrics (Kafka lag).
-   **Database:** **Managed PostgreSQL (RDS/Cloud SQL)**. Reduces operational overhead (backups, patching). We enable Multi-AZ for HA and Read Replicas for scaling `GET` traffic.
-   **Messaging:** **Managed Kafka (MSK/Confluent)**. Essential for durability and high-throughput event streaming.
-   **IaC:** **Terraform**. All infrastructure is defined as code to ensure reproducibility across Dev, Staging, and Prod environments.

### Cost Management
-   **Spot Instances:** Use Spot/Preemptible nodes for stateless background workers (tolerant to interruption), saving ~70% on compute.
-   **Storage Tiering:** Lifecycle policies on S3 to move old media to Infrequent Access (IA) storage after 30 days.
-   **Auto-scaling:** Aggressive scale-down policies during off-peak hours.

---

## 5. Delivery & Operations

### CI/CD Pipeline
1.  **CI:** On PR, run unit tests, linting, and SAST (SonarQube). Build Docker images.
2.  **CD (Staging):** Deploy to staging namespace. Run integration tests and lightweight load tests.
3.  **CD (Production):** Canary deployment. Route 5% of traffic to new version. Monitor error rates and latency. If healthy, roll out to 100%.

### Observability
-   **Metrics (Prometheus/Grafana):**
    -   *RED Method:* Rate, Errors, Duration for all HTTP endpoints.
    -   *Business Metrics:* Posts per minute, Active Users, Feed Latency.
-   **Tracing (OpenTelemetry):** End-to-end tracing to identify bottlenecks (e.g., "Why is the feed slow? Is it the DB or Redis?").
-   **Logs (ELK/Loki):** Structured JSON logs with `trace_id` for correlation.

### Reliability & Recovery
-   **Circuit Breakers:** Implemented in the API client. If the `FeedService` fails, fallback to a cached "popular posts" list rather than 500 error.
-   **Disaster Recovery:**
    -   **RPO:** < 5 min (Async replication to standby region).
    -   **RTO:** < 1 hour (Automated failover scripts).
    -   **Backups:** Daily DB snapshots + Continuous WAL archiving.

### Operational Scenarios
-   **Scenario: API Latency Spike.**
    1.  **Alert:** PagerDuty triggers on "P99 Latency > 500ms".
    2.  **Diagnose:** Check Grafana. If DB CPU is high, check `pg_stat_statements` for slow queries.
    3.  **Remediate:** If a specific query is the culprit, add an index or temporarily enable aggressive caching. If load is general, scale up read replicas.

---

## Running the Project

### Prerequisites
- Docker & Docker Compose
- Python 3.9+

### Quick Start
1.  Start the services:
    ```bash
    docker-compose up -d
    ```
2.  Access the API documentation:
    -   Open http://localhost:8000/docs

### Project Structure
-   `app/`: Application source code
    -   `api/`: API endpoints and routers
    -   `core/`: Configuration and database setup
    -   `domain/`: Business logic and database models
    -   `schemas/`: Pydantic models for request/response validation
-   `terraform/`: Infrastructure as Code (GCP)
