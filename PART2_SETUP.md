# Part 2 setup — Terraform + EKS + Jenkins/SonarQube/Nexus wiring

This is the reference doc for everything added in Part 2: `infra/terraform`
(VPC + EKS), `helm/smartdockershrinker` (the deploy chart), the extended
`Jenkinsfile` (SonarQube + Nexus + EKS deploy), and `sonar-project.properties`.

It assumes your Jenkins, SonarQube, and Nexus already run on AWS (per your
setup) — this doc does **not** install those; it wires the repo to them and
adds a new EKS cluster as the deploy target.

Work through the steps in order — each one depends on the previous one
actually working, not just being run.

## 0. Prerequisites on your PC

```
terraform -version   # >= 1.5
aws --version         # AWS CLI v2
kubectl version --client
helm version
```

Install whichever are missing, then confirm your AWS CLI is authenticated
against the same account Jenkins/SonarQube/Nexus run in:

```
aws sts get-caller-identity
```

## 1. Provision the network + EKS cluster (from your PC)

Terraform is applied manually from your PC on purpose — Jenkins never runs
`terraform apply`/`destroy`, so a bad pipeline run can never touch the
cluster's existence, only what's deployed inside it.

```
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`: set `aws_region` to match where Jenkins/SonarQube/
Nexus already live, and leave `additional_eks_access_entries` for step 3
(you don't have the Jenkins IAM role ARN yet).

```
terraform init
terraform plan
terraform apply
```

This takes ~12-15 minutes (EKS control plane provisioning is slow). When it
finishes:

```
terraform output configure_kubectl
# run the command it prints, e.g.:
aws eks update-kubeconfig --name smartdockershrinker-eks --region eu-central-1
kubectl get nodes
```

You should see 2 nodes in `Ready` state. If this doesn't work, stop here —
nothing downstream will work either.

## 2. One-time cluster bootstrap: ingress controller

The Helm chart's `ingress.yaml` needs an ingress controller running in the
cluster; EKS doesn't ship one.

```
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace
kubectl get svc -n ingress-nginx
```

Note the `EXTERNAL-IP` (a Classic/NLB DNS name) on the `ingress-nginx-controller`
service — that's what `ingress.host` in `helm/smartdockershrinker/values.yaml`
should eventually point to via DNS (CNAME), once you have a domain.

## 3. Grant your Jenkins EC2 role cluster access

Find the IAM role attached to the Jenkins EC2 instance (EC2 console →
instance → IAM Role, or `aws sts get-caller-identity` run from inside the
Jenkins box). Then either:

- Add it to `additional_eks_access_entries` in `terraform.tfvars` and
  re-run `terraform apply` (preferred — stays in code), or
- One-off, without touching Terraform:
  ```
  aws eks create-access-entry \
    --cluster-name smartdockershrinker-eks \
    --principal-arn arn:aws:iam::<account-id>:role/jenkins-ec2-role
  aws eks associate-access-policy \
    --cluster-name smartdockershrinker-eks \
    --principal-arn arn:aws:iam::<account-id>:role/jenkins-ec2-role \
    --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
    --access-scope type=cluster
  ```

Also make sure the Jenkins EC2's security group / outbound rules can reach
the EKS API endpoint (public endpoint restricted by
`eks_public_access_cidrs` in `terraform.tfvars` — add Jenkins' Elastic IP
there if you narrowed it from the wide-open default).

## 4. Install missing CLIs on the Jenkins agent

SSH into the Jenkins EC2 (or its agent, if separate) and confirm/install:
`docker`, `python3`, `aws` CLI v2, `kubectl`, `helm`, `sonar-scanner` CLI.
The Jenkinsfile's "Verify Toolchain" stage will fail fast and name whichever
is missing.

## 5. Jenkins credentials + SonarQube server config

In Jenkins:

- **Manage Jenkins → Credentials** → add a "Username with password"
  credential, ID `nexus-credentials` (Nexus user + a Nexus-generated
  token/password — not your personal Nexus login password if you can avoid
  it).
- **Manage Jenkins → System → SonarQube servers** → add a server named
  exactly `SonarQube`, URL of your Nexus/SonarQube EC2, and an auth token
  (generate it in SonarQube: My Account → Security → Generate Token) stored
  as a Jenkins "Secret text" credential and selected here.
- In SonarQube itself: **Administration → Configuration → Webhooks** → add
  one pointing at `http://<jenkins-host>:8080/sonarqube-webhook/` so the
  `waitForQualityGate` stage in the Jenkinsfile actually gets notified
  instead of just timing out after 5 minutes.

Set `NEXUS_REGISTRY` / `NEXUS_REPO` / `AWS_REGION` / `EKS_CLUSTER_NAME` as
Jenkins job (or global) environment variables if your values differ from
the defaults baked into the `Jenkinsfile`'s `environment {}` block.

## 6. Connect GitHub → Jenkins

1. In Jenkins, create a Pipeline job (or Multibranch Pipeline) pointing at
   this repo, script path `Jenkinsfile`. Enable "GitHub hook trigger for
   GITScm polling" under Build Triggers.
2. On GitHub: repo → **Settings → Webhooks → Add webhook**
   - Payload URL: `http://<jenkins-public-address>:8080/github-webhook/`
   - Content type: `application/json`
   - Events: just the push event is enough to start.
3. Exposing Jenkins on a raw port over HTTP is fine to get moving, but put
   it behind an ALB + ACM certificate + a real domain before this repo (or
   its webhook secret) is anything other than a personal project — a bare
   `:8080` endpoint accepting unauthenticated webhook POSTs is a soft spot.

## 7. First real run — verify end to end

Push a trivial commit to `main` and watch the Jenkins build. Confirm, in
order (stop at the first one that doesn't check out):

1. Jenkins stage view shows all stages green.
2. SonarQube project dashboard (`smartdockershrinker`) shows a fresh
   analysis with a pass/fail quality gate badge.
3. Nexus repository browser shows `docker-hosted/smartdockershrinker` with
   a new `shrunk-<build-number>` and `latest` tag.
4. `kubectl get pods -n smartdockershrinker` shows the deployment's pods
   `Running` and `READY`.
5. `curl http://<ingress-nginx external DNS>/healthz` (send the `Host:
   shrinker.example.com` header, or set your `/etc/hosts`, until you wire
   up real DNS) returns `{"status":"healthy",...}`.

## Still open after this

- Real DNS + TLS for the ingress host (currently `shrinker.example.com` /
  `tls: false` placeholders in `values.yaml`).
- Remote Terraform state (S3 + DynamoDB lock table) once more than one
  person applies this — see the commented-out `backend "s3"` block in
  `infra/terraform/providers.tf`.
- Cluster/node autoscaling beyond the pod-level HPA already wired up
  (Cluster Autoscaler or Karpenter) — not needed until you're regularly
  hitting the node group's `node_max_size`.
- Part 3 from the roadmap (the Visual Semantic Translator / RTL
  Auto-Flipper product) — not started.
