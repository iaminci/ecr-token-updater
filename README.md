# ECR Token Refresh Automation

This project provides an automated solution for refreshing AWS ECR (Elastic Container Registry) authentication tokens and storing them in Infisical secrets management.

## Overview

AWS ECR tokens expire after 12 hours. This automation runs a Kubernetes CronJob every 8 hours to retrieve fresh ECR tokens and update them in Infisical, ensuring your applications always have valid credentials. A one-time **Job** in the same manifest runs immediately after deploy so you do not wait for the first CronJob tick.

The solution uses a custom Docker image that packages AWS CLI (installed via pip), Infisical CLI, and an automation script into a lightweight Alpine Linux container.

## Components

### 1. Dockerfile
Builds a lightweight Alpine-based container image with:
- AWS CLI for ECR authentication
- Infisical CLI for secrets management
- Bash and utilities (curl, jq)
- The ECR token update script

### 2. Manifest (`ecr-auth-cronjob.yaml`)
Single file with two resources (separated by `---`):

**CronJob (`ecr-token-refresh`)** — scheduled refresh.

**Key configuration:**
- **Schedule**: `0 */8 * * *` (every 8 hours)
- **Timeout**: 600 seconds (10 minutes)
- **Retry policy**: `backoffLimit` 3
- **Concurrency**: `Forbid` (no overlapping jobs)
- **History**: 3 successful / 5 failed jobs retained

**Job (`ecr-token-refresh-init`)** — runs once when you first apply the manifest, using the same image and environment as the CronJob, so the secret is updated immediately after deploy.

### 3. Secret (`secret.yaml`)
Kubernetes Secret containing AWS credentials and Infisical token.

### 4. Update Script (`update-ecr-token.sh`)
Bash script that:
- Retrieves ECR authentication token from AWS
- Updates the token in Infisical using the CLI
- Validates all required environment variables
- Provides comprehensive error handling

Replace example region, Infisical project ID, and environment values in `ecr-auth-cronjob.yaml` with your own; do not commit real credentials in `secret.yaml`.

## Prerequisites

- Kubernetes cluster (version 1.21+)
- Docker (only if building custom image - Option B)
- Docker Hub account or private container registry (only if building custom image - Option B)
- AWS account with ECR access
- Infisical account and project
- `kubectl` configured for your cluster
- AWS IAM credentials with ECR permissions

## Required IAM Permissions

Your AWS credentials need the following permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken"
      ],
      "Resource": "*"
    }
  ]
}
```

## Setup Instructions

### Step 1: Choose Your Docker Image Option

You have two options for the Docker image:

#### Option A: Use the Pre-built Image (Recommended for Quick Start)

Use the publicly available image directly without building anything:

```yaml
# In ecr-auth-cronjob.yaml
image: iaminci/ecr-token-updater:latest
```

This image is ready to use with the required environment variables. Skip to Step 2.

#### Option B: Build Your Own Custom Image

Build your own image if you want to:
- Modify the update script (`update-ecr-token.sh`)
- Customize the Docker image dependencies
- Use a private container registry
- Have full control over the image

```bash
# Build the image
docker build -t your-dockerhub-username/ecr-token-updater:latest .

# Push to Docker Hub (or your private registry)
docker push your-dockerhub-username/ecr-token-updater:latest
```

Then update the image reference in `ecr-auth-cronjob.yaml` for both the CronJob and the `ecr-token-refresh-init` Job:

```yaml
containers:
- name: token-updater
  image: your-dockerhub-username/ecr-token-updater:latest
```

### Step 2: Prepare Your Credentials

Encode your credentials in base64:

```bash
echo -n 'your_aws_access_key_id' | base64
echo -n 'your_aws_secret_access_key' | base64
echo -n 'your_infisical_token' | base64
```

### Step 3: Update the Secret

Edit `secret.yaml` and replace the placeholder values with your base64-encoded credentials:

```yaml
data:
  AWS_ACCESS_KEY_ID: <your_base64_encoded_access_key>
  AWS_SECRET_ACCESS_KEY: <your_base64_encoded_secret_key>
  INFISICAL_TOKEN: <your_base64_encoded_infisical_token>
```

### Step 4: Configure the CronJob and Init Job

Update the environment variables in `ecr-auth-cronjob.yaml` (under both the CronJob and the `ecr-token-refresh-init` Job):

- **AWS_REGION**: Your AWS region (e.g., `ap-south-1`)
- **INFISICAL_URL**: Your Infisical instance URL (defaults to `https://app.infisical.com`)
- **INFISICAL_PROJECT_ID**: Your Infisical project ID
- **INFISICAL_ENV**: Target environment (e.g., `dev`, `staging`, `prod`)

### Step 5: Deploy to Kubernetes

Apply the Secret first, then the manifest that contains the CronJob and init Job:

```bash
kubectl apply -f secret.yaml
kubectl apply -f ecr-auth-cronjob.yaml
```

The init Job `ecr-token-refresh-init` starts as soon as the Secret exists. If you apply the same Job again later, Kubernetes will not re-run a completed Job with the same name; delete it first if you need another immediate run: `kubectl delete job ecr-token-refresh-init`, then `kubectl apply -f ecr-auth-cronjob.yaml` again.

### Step 6: Verify Deployment

```bash
# Check CronJob status
kubectl get cronjob ecr-token-refresh

# View CronJob details
kubectl describe cronjob ecr-token-refresh

# List Jobs created by the CronJob (controller sets this label)
kubectl get jobs -l cronjob.kubernetes.io/name=ecr-token-refresh

# Init Job (first run on deploy)
kubectl logs job/ecr-token-refresh-init

# Logs for a specific CronJob-created Job — use the exact name from kubectl get jobs
kubectl logs job/ecr-token-refresh-<timestamp-suffix> --tail=50
```

## Configuration Reference

### Environment Variables

| Variable | Required | Description | Default |
|----------|----------|-------------|---------|
| `AWS_ACCESS_KEY_ID` | Yes | AWS access key ID | - |
| `AWS_SECRET_ACCESS_KEY` | Yes | AWS secret access key | - |
| `AWS_REGION` | Yes | AWS region for ECR | - |
| `INFISICAL_TOKEN` | Yes | Infisical authentication token | - |
| `INFISICAL_PROJECT_ID` | Yes | Infisical project identifier | - |
| `INFISICAL_ENV` | Yes | Target environment in Infisical | - |
| `INFISICAL_URL` | No | Infisical instance URL | `https://app.infisical.com` |

## Monitoring

### Check Job History

```bash
# Jobs created by the CronJob
kubectl get jobs -l cronjob.kubernetes.io/name=ecr-token-refresh

# Field selectors (optional) — combine with the label above if your kubectl version supports it
kubectl get jobs -l cronjob.kubernetes.io/name=ecr-token-refresh --field-selector status.successful=1
kubectl get jobs -l cronjob.kubernetes.io/name=ecr-token-refresh --field-selector status.failed=1
```

### View Logs

```bash
# Init Job (one-time deploy)
kubectl logs job/ecr-token-refresh-init --tail=100

# A CronJob-created Job — copy the full job name from: kubectl get jobs
kubectl logs job/<full-job-name> --tail=100
```

## Troubleshooting

### Job Fails to Start

**Problem**: CronJob doesn't create jobs

**Solution**:
```bash
# Check CronJob configuration
kubectl describe cronjob ecr-token-refresh

# Verify the secret exists
kubectl get secret infisical-credentials
```

### Authentication Errors

**Problem**: AWS authentication fails

**Solution**:
- Verify your AWS credentials are correct
- Check IAM permissions include `ecr:GetAuthorizationToken`
- Ensure credentials are properly base64 encoded

### Infisical Update Fails

**Problem**: Token retrieval succeeds but Infisical update fails

**Solution**:
- Verify your Infisical token is valid
- Check project ID and environment name are correct
- Ensure the Infisical URL is accessible from your cluster

### Manual Test Run

To trigger the same workload as the CronJob without waiting for the schedule, use a **unique** Job name each time:

```bash
JOB="ecr-token-refresh-manual-$(date +%s)"
kubectl create job "$JOB" --from=cronjob/ecr-token-refresh
kubectl logs -f "job/$JOB"
```

## Security Best Practices

1. **Use RBAC**: Limit access to the namespace containing the secret
2. **Rotate Credentials**: Regularly rotate AWS and Infisical credentials
3. **Use Service Accounts**: Consider using AWS IRSA (IAM Roles for Service Accounts) instead of static credentials
4. **Monitor Logs**: Set up alerts for job failures
5. **Encrypt Secrets**: Enable encryption at rest for Kubernetes secrets

## Customization

### Change Schedule

Modify the `schedule` field under the CronJob in `ecr-auth-cronjob.yaml`. Example — every 10 hours:

```yaml
spec:
  schedule: "0 */10 * * *"  # Every 10 hours
```

**Current schedule**: Every 8 hours (`0 */8 * * *`).

### Adjust Timeout

Modify the `activeDeadlineSeconds` on the CronJob `jobTemplate` and/or the init Job:

```yaml
activeDeadlineSeconds: 300  # 5 minutes
```

### Modify Retry Behavior

Adjust the `backoffLimit`:

```yaml
backoffLimit: 5  # Retry up to 5 times
```

## Cleanup

To remove all resources:

```bash
kubectl delete cronjob ecr-token-refresh
kubectl delete job ecr-token-refresh-init
kubectl delete secret infisical-credentials
kubectl delete jobs -l cronjob.kubernetes.io/name=ecr-token-refresh
```

## License

This project is provided as-is for automation of ECR token management.

## Support

For issues or questions:
- Check Kubernetes events: `kubectl get events --sort-by='.lastTimestamp'`
- Review init Job logs: `kubectl logs job/ecr-token-refresh-init`
- Review CronJob-created jobs: `kubectl get jobs -l cronjob.kubernetes.io/name=ecr-token-refresh` then `kubectl logs job/<name>`
- Verify AWS CLI works: Test AWS credentials outside the container
