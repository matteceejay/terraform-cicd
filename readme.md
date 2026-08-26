# Secure CI/CD Pipeline: Terraform + GitHub Actions + ECS

A production-style CI/CD pipeline that builds a container image, scans it for
secrets and vulnerabilities, pushes it to a private ECR repository, and
deploys it to Amazon ECS (Fargate) across isolated dev/staging/prod
environments — all provisioned with Terraform and driven by GitHub Actions
using short-lived OIDC credentials (no long-lived AWS keys anywhere).

This README is written so a peer can clone this repo and stand up their own
copy end to end, including every place they need to swap in their own
AWS account, domain, and GitHub details.

---

## Table of contents

1. [Architecture overview](#architecture-overview)
2. [Prerequisites](#prerequisites)
3. [Repository structure](#repository-structure)
4. [Setup — step by step](#setup--step-by-step)
5. [Every placeholder you need to change](#every-placeholder-you-need-to-change)
6. [How the pipeline flows](#how-the-pipeline-flows)
7. [Security decisions, explained](#security-decisions-explained)
8. [Extending to staging and prod](#extending-to-staging-and-prod)
9. [Troubleshooting — real issues we hit](#troubleshooting--real-issues-we-hit)
10. [License](#license)

---

## Architecture overview

**Two layers, applied separately:**

- **`global-env/`** — applied once per AWS account. Creates the shared ECR
  repository, looks up (or creates) the GitHub OIDC provider, and creates the
  build role that GitHub Actions assumes to push images.
- **`environments/<env>/`** — applied once per environment (`dev`, `staging`,
  `prod`). Creates that environment's VPC, ALB, ECS cluster/service, task
  IAM roles, and its own deploy role — fully isolated Terraform state per
  environment, so a mistake in `dev` can never touch `prod`.

**Pipeline flow (three GitHub Actions workflows, chained):**

```
push to main
     │
     ▼
ci-scan.yml          gitleaks (secrets) → SonarCloud (SAST + quality gate)
     │  (on success, via workflow_run)
     ▼
build-and-push.yml   assume OIDC build role → docker build → Trivy scan → push to ECR
     │  (on success, via workflow_run)
     ▼
deploy.yml           assume OIDC deploy role → register new task def → update ECS service
```

Every image is built and scanned **once**, tagged by commit SHA, then that
same image is what gets deployed — never rebuilt per environment.

---

## Prerequisites

Before you start, have these ready:

- An **AWS account** with permissions to create IAM roles/policies, VPCs,
  ALBs, ECS resources, ECR repos, and Route 53 records.
- **Terraform** installed locally (this project was built against the
  `hashicorp/aws` provider v6.x).
- **AWS CLI** installed and configured with credentials that can run
  `terraform apply` (this is for your local bootstrap only — the pipeline
  itself never uses long-lived keys).
- **A GitHub repository** you control, with **Actions enabled**.
- **Docker** installed locally, if you want to test image builds before
  pushing.
- **A domain with a Route 53 hosted zone**, and an **ACM certificate**
  covering it. Read the note under Placeholders about wildcard certs — a
  `*.yourdomain.com` cert only covers one subdomain level
  (`app.yourdomain.com`, not `app.dev.yourdomain.com`).
- **A SonarCloud account** with an organization set up (free for public
  repos). This project uses SonarCloud, not self-hosted SonarQube.

---

## Repository structure

```
.
├── .github/
│   └── workflows/
│       ├── ci-scan.yml            # gitleaks + SonarCloud, runs on every push to main
│       ├── build-and-push.yml     # build image → Trivy scan → push to ECR
│       └── deploy.yml             # deploy to ECS (dev job now; staging/prod added the same way)
│
├── global-env/                    # applied ONCE per AWS account
│   ├── ecr.tf                     # shared ECR repository + KMS key + lifecycle policy
│   ├── oidc-provider.tf           # looks up the GitHub OIDC provider (does not create it)
│   ├── build-role.tf              # IAM role GitHub Actions assumes to build & push images
│   └── backend.tf
│
├── modules/                       # reusable, no state of their own
│   ├── vpc/                       # VPC, public/private subnets, IGW, NAT gateway(s)
│   ├── alb/                       # ALB, target group, HTTPS listener, Route 53 record
│   ├── ecs-service/                # ECS cluster, task definition, service, security group
│   ├── ecs-task-roles/             # ECS execution role + task role (app runtime permissions)
│   └── deploy-role/                 # per-environment IAM role for the deploy workflow
│
├── environments/
│   ├── dev/
│   │   ├── main.tf                 # wires all modules together for dev
│   │   ├── variables.tf
│   │   ├── terraform.tfvars         # dev's actual values — YOU edit this
│   │   ├── backend.tf                # dev's own isolated state
│   │   └── outputs.tf
│   ├── staging/                     # same shape as dev, once you build it
│   └── prod/                        # same shape as dev, once you build it
│
├── Dockerfile                      # builds the app image (nginx serving static HTML by default)
├── index.html                      # the app itself — replace with your own content
├── sonar-project.properties         # SonarCloud project/organization keys
├── .gitignore
└── README.md
```

---

## Setup — step by step

### 1. Clone the repo and update placeholders

Clone this repo, then work through the full list in
[Every placeholder you need to change](#every-placeholder-you-need-to-change)
below before applying anything. Skipping this step is the most common
source of confusing errors — Terraform and GitHub Actions will both run
"successfully" against wrong values and fail somewhere downstream instead.

### 2. Bootstrap the shared infrastructure

```bash
cd global-env/
terraform init
terraform apply
```

This creates the ECR repository, resolves the GitHub OIDC provider, and
creates the build role. Note the outputs — you'll need the build role ARN
later if you ever reference it outside this repo.

> **If `terraform apply` fails with `EntityAlreadyExists` on the OIDC
> provider:** this is expected if you (or another project in the same AWS
> account) already registered `https://token.actions.githubusercontent.com`
> as an OIDC provider — it's scoped to the AWS account, not per-project.
> `oidc-provider.tf` already uses a `data` lookup instead of creating one,
> specifically to handle this.

### 3. Apply the dev environment

```bash
cd environments/dev/
terraform init
terraform apply
```

This creates dev's VPC, ALB, ECS cluster/service, task roles, and deploy
role. **Expect the ECS service to show 0 healthy tasks at this point** —
there's no image in ECR yet, so this is normal, not a failure.

Note the `deploy_role_arn` output — you'll need it for a GitHub repo
variable in the next step.

### 4. Configure GitHub repository variables

Go to your repo → **Settings → Secrets and variables → Actions → Variables
tab** and add:

| Variable name | Value | Where it comes from |
|---|---|---|
| `AWS_ACCOUNT_ID` | your 12-digit AWS account ID | `aws sts get-caller-identity` |
| `AWS_REGION` | e.g. `us-east-1` | wherever you're deploying |
| `ECR_REPOSITORY_NAME` | the name set in `global-env/ecr.tf` | e.g. `my-app` |
| `DEV_DEPLOY_ROLE_ARN` | the `deploy_role_arn` output from step 3 | `terraform output deploy_role_arn` in `environments/dev` |

These are **variables**, not secrets — none of this is sensitive, it's all
identifiers.

### 5. Configure GitHub repository secrets

Same location, **Secrets tab** instead:

| Secret name | Value | Where it comes from |
|---|---|---|
| `SONAR_TOKEN` | a token generated in SonarCloud | SonarCloud → My Account → Security → Generate Tokens |

`GITHUB_TOKEN` needs no setup — GitHub provides it automatically per run.

### 6. Create a GitHub Environment named `dev`

Go to **Settings → Environments → New environment**, name it exactly `dev`.
No protection rules needed for dev — this exists purely so the deploy
role's trust policy (which checks for a GitHub Environment claim in the
OIDC token) has something to match against. You'll add `staging` and
`prod` the same way later, with required reviewers on `prod`.

### 7. Set up SonarCloud

1. On sonarcloud.io, click **+ → Analyze new project**, connect your GitHub
   repo.
2. **Immediately go to Administration → Analysis Method and turn OFF
   Automatic Analysis.** This project uses CI-based analysis via the
   workflow — having both enabled causes every scan to fail.
3. Note your **Organization Key** and **Project Key** from
   Administration → General Settings, and put them in
   `sonar-project.properties` (see placeholders below).

### 8. Push and watch it run

```bash
git add .
git commit -m "Initial setup"
git push -u origin main
```

Watch the **Actions** tab. `ci-scan.yml` should run first, then
`build-and-push.yml`, then `deploy.yml`. Once all three succeed, your app
should be live at whatever subdomain you configured.

---

## Every placeholder you need to change

| File | What to change | Example |
|---|---|---|
| `global-env/ecr.tf` | ECR repository name | `"my-app"` |
| `global-env/build-role.tf` | The `sub` condition — see note below on immutable format | see below |
| `environments/dev/terraform.tfvars` | `vpc_cidr` | `"10.0.0.0/16"` (use a different range per environment) |
| `environments/dev/terraform.tfvars` | `certificate_arn` | your ACM cert ARN |
| `environments/dev/terraform.tfvars` | `hosted_zone_name` | your Route 53 zone, e.g. `"yourdomain.com"` |
| `environments/dev/terraform.tfvars` | `subdomain_name` | e.g. `"app-dev.yourdomain.com"` — see wildcard cert note below |
| `environments/dev/terraform.tfvars` | `github_repo_immutable` | see note below |
| `environments/dev/terraform.tfvars` | `github_environment_name` | `"dev"` |
| `environments/dev/terraform.tfvars` | `oidc_provider_arn` | `arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com` |
| `.github/workflows/build-and-push.yml` | `role-to-assume` ARN | uses `${{ vars.AWS_ACCOUNT_ID }}` — just needs the variable set, no file edit |
| `.github/workflows/deploy.yml` | `role-to-assume` ARN | uses `${{ vars.DEV_DEPLOY_ROLE_ARN }}` — same, no file edit needed once the variable exists |
| `sonar-project.properties` | `sonar.organization`, `sonar.projectKey` | from your SonarCloud project settings |
| `Dockerfile` / `index.html` | replace with your actual app | — |

### ⚠️ About the GitHub OIDC "immutable subject claim" format

**If your GitHub repository was created after July 15, 2026**, GitHub uses a
new subject claim format for OIDC tokens by default:

```
repo:OWNER@OWNER_ID/REPO@REPO_ID:ref:refs/heads/main
```

instead of the older, simpler:

```
repo:OWNER/REPO:ref:refs/heads/main
```

If you use the plain format on a repo created after that date, every OIDC
role assumption will fail with `Not authorized to perform
sts:AssumeRoleWithWebIdentity` — and the error gives no hint that the
format itself is the problem.

**To find your repo's actual IDs**, add a temporary debug step to any
workflow before the OIDC step:

```yaml
- name: DEBUG — print actual OIDC token claims
  env:
    ACTIONS_ID_TOKEN_REQUEST_URL: ${{ env.ACTIONS_ID_TOKEN_REQUEST_URL }}
    ACTIONS_ID_TOKEN_REQUEST_TOKEN: ${{ env.ACTIONS_ID_TOKEN_REQUEST_TOKEN }}
  run: |
    TOKEN=$(curl -sSL -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
      "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=sts.amazonaws.com" | jq -r '.value')
    echo $TOKEN | cut -d. -f2 | base64 -d 2>/dev/null | jq .
```

Run it once, read the `sub` field from the output, then **delete the debug
step** — it's diagnostic only and shouldn't stay in a real workflow.

### ⚠️ About wildcard ACM certificates

A cert for `*.yourdomain.com` covers exactly **one subdomain level** —
`app.yourdomain.com` is covered, but `app.dev.yourdomain.com` is **not**
(that's two levels deep). If you're using a single wildcard cert across
dev/staging/prod, use hyphenated single-level subdomains instead of dotted
ones:

- ✅ `app-dev.yourdomain.com`, `app-staging.yourdomain.com`,
  `app.yourdomain.com`
- ❌ `dev.app.yourdomain.com`, `staging.app.yourdomain.com`

---

## How the pipeline flows

**`ci-scan.yml`** — triggers on push to `main`. Runs gitleaks first (fails
fast on any hardcoded secret), then SonarCloud (SAST + a quality gate that
actually fails the build on violations, not just reports them).

**`build-and-push.yml`** — triggers only after `ci-scan.yml` succeeds
(via `workflow_run`, not a second `push` trigger — this avoids a race
between the two). Assumes the build role via OIDC (no stored AWS keys),
builds the Docker image, scans it with Trivy (fails on HIGH/CRITICAL CVEs),
and pushes to ECR tagged by the exact commit SHA that was scanned.

**`deploy.yml`** — triggers after `build-and-push.yml` succeeds. Assumes
the environment's deploy role, downloads the current ECS task definition,
swaps in the new image tag, registers a new revision, and updates the
service — waiting for the new task to actually pass health checks before
reporting success.

---

## Security decisions, explained

- **No long-lived AWS credentials anywhere.** Every AWS interaction from
  GitHub Actions uses OIDC to assume a short-lived role.
- **Separate build and deploy roles**, each scoped to only what that stage
  needs — the build role can push images but has zero ECS permissions; the
  deploy role can update ECS but has zero ECR push permissions.
- **Deploy roles are keyed to a GitHub Environment claim**, not just
  repo/branch — this is what makes "manual approval" for prod an
  AWS-enforced boundary, not just a workflow-file convention.
- **Images are immutable and SHA-tagged** — `image_tag_mutability =
  "IMMUTABLE"` on the ECR repo means a tag can never be silently
  overwritten.
- **Every environment has its own Terraform state** — a bad `apply` in
  `dev` cannot touch `staging` or `prod`.
- **Every third-party GitHub Action is pinned to a full commit SHA**, not a
  mutable version tag — a tag can be moved by the action's maintainer (or
  an attacker who compromises their account); a SHA cannot.

---

## Extending to staging and prod

1. Copy `environments/dev/` to `environments/staging/` and
   `environments/prod/`.
2. Update each `terraform.tfvars` — different `vpc_cidr`, different
   `subdomain_name`, and for **prod specifically**: set
   `single_nat_gateway = false` (one NAT gateway is a single point of
   failure) and `deletion_protection = true` on the ALB.
3. `terraform apply` each new environment directory.
4. Create GitHub Environments named `staging` and `prod`. **Add required
   reviewers to `prod`** — this is what makes the manual-approval gate
   real.
5. Add `STAGING_DEPLOY_ROLE_ARN` and `PROD_DEPLOY_ROLE_ARN` as repo
   variables.
6. Add corresponding jobs to `deploy.yml`, matching the shape of
   `deploy-dev` but with `environment: staging` / `environment: prod` and
   the matching variables.

No module changes are needed — `vpc`, `alb`, `ecs-service`,
`ecs-task-roles`, and `deploy-role` were all built to be called this way
from the start.

---

## Troubleshooting — real issues we hit

- **`Not authorized to perform sts:AssumeRoleWithWebIdentity`** — almost
  always the OIDC `sub` condition not matching. See the immutable subject
  claim note above; use the debug step to see the real token claims rather
  than guessing.
- **`AccessDeniedException` on `ecs:DescribeTaskDefinition` or
  `ecs:RegisterTaskDefinition`** — these two IAM actions **do not support
  resource-level scoping**, only `resources = ["*"]`. If they're bundled
  into a statement with ARN-scoped resources, IAM rejects them. Give them
  their own statement.
- **SonarCloud: "You are running CI analysis while Automatic Analysis is
  enabled"** — a SonarCloud project setting, not a workflow bug. Turn off
  Automatic Analysis under Administration → Analysis Method.
- **SonarCloud scanner: "Expected URL scheme... no scheme was found"** —
  `SONAR_HOST_URL` wasn't set. For SonarCloud specifically, hardcode it to
  `https://sonarcloud.io` (it's not sensitive) rather than pulling from an
  unset secret.
- **`docker push` fails with `invalid reference format`** — usually means
  one or more of the `vars.AWS_ACCOUNT_ID` / `vars.AWS_REGION` /
  `vars.ECR_REPOSITORY_NAME` repo variables is missing or empty.
- **Workflow stuck in "Queued" indefinitely** — check
  [githubstatus.com](https://www.githubstatus.com) before assuming it's
  your pipeline. GitHub Actions does have occasional platform-wide
  incidents.
- **`.terraform/` accidentally committed, push rejected for file size** —
  `.terraform/` and `*.tfstate*` should never be committed, remote backend
  or not. Add them to `.gitignore` before your first commit.
- **Workflow files not triggering at all** — GitHub only ever reads
  workflows from `.github/workflows/` at the **true repo root**. A file
  nested under any other folder (e.g. `modules/.github/workflows/`) is
  invisible to Actions.

---

## License

Add your license of choice here (MIT is a common default for teaching
projects like this one).