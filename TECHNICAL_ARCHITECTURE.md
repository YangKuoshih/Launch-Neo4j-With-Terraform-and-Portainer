# Neo4j Enterprise Platform - Technical Architecture

## Overview
This repository contains a complete Infrastructure as Code (IaC) solution for deploying a Neo4j Enterprise platform on AWS using Terraform. The platform provides a secure, cost-optimized, and automated Neo4j Enterprise environment for development and experimentation.

## Architecture Components

### 🏗️ Infrastructure Layer (Terraform)

#### Core Infrastructure (`infrastructure.tf`)
- **VPC**: Custom VPC with public subnet for Neo4j deployment
- **Security Groups**: Configured for Neo4j (7474, 7687), NeoDash (5005), and Portainer (8102)
- **Elastic IP**: Static IP address for consistent access
- **Route Tables**: Public routing for internet access

#### Compute Resources (`main.tf`)
- **EC2 Instance**: Amazon Linux 2 instance with Docker pre-installed
- **Instance Profile**: IAM role with necessary permissions for AWS services
- **Key Pair**: SSH access using generated RSA keys
- **Auto-tagging**: `AutoStopStart=True` for automated scheduling

#### Security & Secrets Management (`secrets.tf`)
- **AWS Secrets Manager**: Secure storage for Neo4j credentials and JWT tokens
- **IAM Policies**: Least-privilege access for EC2 and AWS services
- **SSH Keys**: Automated generation and secure storage

#### Automation & Scheduling (`main.tf`)
- **EventBridge Scheduler**: Automated EC2 stop/start (3 AM UTC stop, 12 PM UTC start)
- **Cost Optimization**: Automatic instance management to minimize costs
- **SSM Parameters**: Centralized configuration storage

### 🐳 Container Layer (Docker)

#### Neo4j Enterprise (`docker/neo4j/docker-compose.yml`)
- **Neo4j Enterprise Edition**: 30-day evaluation license
- **Ports**: 7474 (HTTP), 7687 (Bolt), 7473 (HTTPS)
- **Volumes**: Persistent data storage
- **Environment**: Configured for development use

#### NeoDash Dashboard (`docker/neo4j/docker-compose.yml`)
- **Port**: 5005
- **Integration**: Connected to Neo4j instance
- **Visualization**: Graph data visualization and dashboards

#### Portainer (`docker/portainer/docker-compose.yml`)
- **Container Management**: Web-based Docker management
- **Port**: 9000 (internal), 8102 (external via Caddy)
- **Security**: Protected by Caddy reverse proxy

#### Caddy Reverse Proxy (`caddy/`)
- **HTTPS Termination**: Automatic SSL certificates
- **Authentication**: Basic auth for Portainer access
- **Configuration**: Modular Caddyfile structure

### 🚀 Deployment & Automation

#### EC2 User Data (`ec2-setup/user-data.sh`)
```bash
# Automated setup includes:
- Docker and Docker Compose installation
- AWS CLI configuration
- Service deployment and startup
- Log configuration
```

#### Launcher System (`launcher.bat`)
- **Quick Access**: Direct URLs to all services
- **Command Shortcuts**: Terraform, AWS CLI, SSH commands
- **Environment Variables**: Dynamic configuration

#### Scripts Directory (`scripts/`)
- **Terraform Helpers**: Apply/destroy automation
- **Data Generation**: Sample datasets for testing
- **Service Management**: Start/stop utilities

## Data Flow Architecture

```
User → Launcher.bat → Services
  ↓
AWS Infrastructure
  ├── EC2 Instance (Docker Host)
  │   ├── Neo4j Enterprise (7474/7687)
  │   ├── NeoDash (5005)
  │   └── Portainer (9000)
  ├── Caddy Proxy (8102) → Portainer
  ├── S3 Bucket (Data Storage)
  └── Secrets Manager (Credentials)
```

## Security Architecture

### Network Security
- **VPC Isolation**: Dedicated virtual network
- **Security Groups**: Port-specific access control
- **Elastic IP**: Static public IP for consistent access
- **SSH Access**: Key-based authentication only

### Secrets Management
- **AWS Secrets Manager**: Encrypted credential storage
- **No Hardcoded Secrets**: All sensitive data externalized
- **IAM Roles**: Service-to-service authentication
- **Git Security**: Comprehensive .gitignore for sensitive files

### Access Control
- **SSH Keys**: RSA 4096-bit encryption
- **Caddy Auth**: Basic authentication for Portainer
- **Neo4j Auth**: Database-level user management
- **AWS IAM**: Least-privilege access policies

## Cost Optimization Features

### Automated Scheduling
- **Daily Stop**: 3:00 AM UTC (off-hours)
- **Daily Start**: 12:00 PM UTC (business hours)
- **EventBridge**: Serverless scheduling (no additional costs)

### Resource Efficiency
- **Single EC2 Instance**: Containerized services
- **Spot Instance Ready**: Can be configured for spot instances
- **S3 Storage**: Cost-effective data persistence
- **Elastic IP**: Prevents IP changes during stop/start cycles

## Monitoring & Observability

### Logging
- **CloudWatch**: EC2 instance logs
- **User Data Logs**: `/var/log/user-data.log`
- **Docker Logs**: Container-level logging
- **SSH Access**: Direct log inspection via launcher

### Health Checks
- **Service URLs**: Direct access verification
- **Portainer Dashboard**: Container health monitoring
- **Neo4j Browser**: Database connectivity testing

## Development Workflow

### Initial Setup
1. **Clone Repository**: `git clone <repo-url>`
2. **Configure AWS**: Set credentials and region
3. **Deploy Infrastructure**: `terraform init && terraform apply`
4. **Access Services**: Use generated `launcher.bat`

### Daily Operations
- **Start Work**: Services auto-start at 12 PM UTC
- **Access Neo4j**: `neo4j` command in launcher
- **Manage Containers**: `portainer` command in launcher
- **SSH Access**: `sshe` command in launcher

### Maintenance
- **Update Infrastructure**: Modify Terraform files, run `tfa`
- **Recreate Instance**: Use `tec2` command for fresh deployment
- **View Logs**: Use `esl` command for real-time logs

## File Structure

```
my-neo4j-enterprise/
├── terraform/           # Infrastructure as Code
│   ├── main.tf         # Core resources & scheduling
│   ├── infrastructure.tf # VPC, networking, compute
│   ├── secrets.tf      # Security & secrets management
│   ├── variables.tf    # Configuration variables
│   └── providers.tf    # Terraform providers
├── docker/             # Container configurations
│   ├── neo4j/         # Neo4j & NeoDash setup
│   └── portainer/     # Container management
├── caddy/             # Reverse proxy configuration
├── ec2-setup/         # Instance initialization
├── scripts/           # Automation utilities
├── keys/              # SSH key storage (gitignored)
└── docs/              # Documentation assets
```

## Technology Stack

### Infrastructure
- **Terraform**: Infrastructure as Code
- **AWS EC2**: Compute platform
- **AWS VPC**: Network isolation
- **AWS Secrets Manager**: Credential management
- **AWS EventBridge**: Scheduling automation

### Application Stack
- **Neo4j Enterprise**: Graph database
- **NeoDash**: Visualization dashboard
- **Portainer**: Container management
- **Caddy**: Reverse proxy & SSL termination
- **Docker**: Containerization platform

### Development Tools
- **Git**: Version control
- **Windows Batch**: Automation scripts
- **Python**: Data generation utilities
- **PowerShell**: Advanced scripting

## Performance Considerations

### Instance Sizing
- **Default**: t3.medium (2 vCPU, 4 GB RAM)
- **Scalable**: Can be adjusted via Terraform variables
- **Storage**: EBS-optimized for database workloads

### Network Performance
- **Elastic IP**: Consistent connectivity
- **VPC**: Optimized routing
- **Security Groups**: Minimal latency overhead

## Disaster Recovery

### Data Persistence
- **EBS Volumes**: Persistent storage across restarts
- **S3 Backup**: Optional backup storage
- **Terraform State**: Infrastructure reproducibility

### Recovery Procedures
1. **Instance Failure**: `terraform apply` recreates infrastructure
2. **Data Loss**: Restore from S3 backups (if configured)
3. **Configuration Drift**: Git repository maintains source of truth

## Future Enhancements

### Planned Features
- **Multi-AZ Deployment**: High availability setup
- **Auto Scaling**: Dynamic instance scaling
- **Monitoring Dashboard**: CloudWatch integration
- **Backup Automation**: Scheduled data backups

### Extensibility Points
- **Additional Services**: Easy Docker Compose additions
- **Custom Domains**: Caddy configuration for custom URLs
- **CI/CD Integration**: GitHub Actions for automated deployment
- **Multi-Environment**: Dev/staging/prod configurations

## Troubleshooting Guide

### Common Issues
1. **Services Not Starting**: Check `esl` logs
2. **Connection Refused**: Verify security group rules
3. **Authentication Failures**: Check Secrets Manager values
4. **Terraform Errors**: Validate AWS credentials and permissions

### Debug Commands
```bash
# View service logs
esl

# SSH into instance
sshe

# Check container status
portainer

# Restart services
# SSH in and run: docker-compose restart
```

This architecture provides a robust, secure, and cost-effective platform for Neo4j Enterprise development and experimentation on AWS.