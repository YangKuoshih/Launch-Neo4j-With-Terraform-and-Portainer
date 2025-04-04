# Architecture Diagram

```mermaid
flowchart TD
    %% AWS Infrastructure
    A[AWS VPC (10.0.0.0/16)]
    B[Public Subnet (10.0.1.0/24)]
    C[Internet Gateway]
    D[Route Table]
    E[Security Group<br/>(SSH, 6000-6999,<br/>7474, 7687, 6464, 6102)]
    
    A --> B
    A --> C
    A --> D
    A --> E

    %% EC2 Instance
    F[EC2 Instance<br/>(with IAM Instance Profile)]
    G[Elastic IP]
    
    B --> F
    F --> G

    %% Docker Containers on EC2
    H[Docker Engine]
    F --> H

    I[Neo4j Container<br/>(HTTP:7474, Bolt:7687)]
    J[Portainer Container]
    K[Caddy Container<br/>(Reverse Proxy)]
    
    H --> I
    H --> J
    H --> K

    %% Caddy Reverse Proxy Setup
    L[Public Port 6464<br/>(Neo4j Reverse Proxy)]
    M[Public Port 6102<br/>(Portainer Reverse Proxy)]
    
    K -- Routes to --> L
    K -- Routes to --> M

    %% Direct Connection to Neo4j Bolt
    I -- Bolt Connection --> N[Port 7687]

    %% Terraform Management
    O[Terraform Modules]
    P[S3 Bucket<br/>(Code Directories)]
    Q[SSM Parameters<br/>(Config Details)]
    
    O --> P
    O --> Q
    P --- F
    Q --- F

    %% User Access
    R[User]
    R -->|Access via Public DNS/IP| G
    R -->|Access via Reverse Proxy| K
    R -->|Direct Bolt Connection| N
