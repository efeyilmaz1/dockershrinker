# CI/CD Pipelines

This project ships the same pipeline — **build the bloated image → run the Shrinker Bot → build the shrunk image → report the size savings → Trivy scan → push & deploy** — on three different CI/CD systems, so the trade-offs between them are visible directly in the repo rather than just described.

| Stage | GitHub Actions (`.github/workflows/shrink_and_deploy.yml`) | Jenkins (`Jenkinsfile`) | GitLab CI (`.gitlab-ci.yml`) |
|---|---|---|---|
| Trigger | `push` to `main` | Configured on the Jenkins job (poll SCM, webhook, or multibranch) | `push`, any branch; deploy stage restricted to the default branch |
| Runner | GitHub-hosted `ubuntu-latest` | Self-managed agent — needs Docker + Python 3 on `PATH` | GitLab-hosted or self-managed runner using `docker:24.0` + `docker:24.0-dind` |
| Passing images between steps | Same job, same Docker daemon — no hand-off needed | Same agent, same Docker daemon — no hand-off needed | Each job gets a fresh `dind` daemon, so the shrunk image is saved with `docker save` and passed as a job artifact |
| Security scan | `aquasecurity/trivy-action` | Official `aquasec/trivy` container against the host's Docker socket | Official `aquasec/trivy` image scanning the artifact tarball directly (`trivy image --input`) — no Docker daemon needed for this job |
| Registry push | Simulated (`echo`) today | Real push if a `dockerhub-credentials` credential exists in Jenkins, otherwise simulated | Real push if `DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN` / `DOCKERHUB_REPO` CI/CD variables are set, otherwise simulated |
| Secrets | GitHub Secrets | Jenkins Credentials store | GitLab CI/CD Variables (masked + protected) |

All three exit the Trivy stage with `exit-code: 0` (report-only, matching the existing GitHub Actions workflow) — flip it to `1` in any of the three files once you're ready to make CRITICAL/HIGH findings actually fail the build (the "Shift-Left" step from the roadmap).

## Why three pipelines

The project roadmap (`Twist_3_4_2_...html`, `Twist_3_4_3_...html`) calls out comparing Jenkins against the GitHub Actions/GitLab CI approach as one of the CI/CD learning goals for Part 1. Having all three configs live side-by-side in the repo makes that comparison concrete: same logic, three different execution models (hosted runner vs. self-managed agent vs. hosted runner + dind), three different secrets stores, three different YAML/DSL dialects.

## Setting up Jenkins

1. Provision (or reuse) a Jenkins controller/agent with Docker and Python 3 installed, and make sure the Jenkins user can talk to the Docker daemon (typically by adding it to the `docker` group).
2. Create a new **Pipeline** job (or a **Multibranch Pipeline** if you want it to build every branch/PR automatically) pointing at this repo, with "Script Path" set to `Jenkinsfile`.
3. Optional — for a real Docker Hub push: **Manage Jenkins → Credentials**, add a "Username with password" credential with ID `dockerhub-credentials` (username = Docker Hub user, password = Docker Hub access token), and set the `DOCKERHUB_REPO` environment variable on the job (e.g. `yourdockerhubuser/smartdockershrinker`).
4. Run the job. Without the credential configured it still runs end-to-end and simulates the push, same as GitHub Actions does today.

## Setting up GitLab CI

1. Either mirror this GitHub repo into a GitLab project (**Settings → Repository → Mirroring repositories**, pull mirror) or import it directly — `.gitlab-ci.yml` at the repo root is picked up automatically once the project has a runner available.
2. Make sure the project has a runner that supports Docker-in-Docker (GitLab's shared runners do by default).
3. Optional — for a real Docker Hub push: **Settings → CI/CD → Variables**, add `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN` (masked), and `DOCKERHUB_REPO`.
4. Push to the default branch (or open a merge request) to trigger the pipeline; the `push_and_deploy` job only runs on the default branch by design.

## Still open from the roadmap's Part 1 checklist

- Real Docker Hub push is now wired up (opt-in via credentials/variables) on all three pipelines instead of only being simulated.
- Getting an actual green check on all three systems still requires: enabling GitLab CI on a mirrored/imported project, and pointing a Jenkins job at this repo — neither can be done from inside this session since they need accounts/infrastructure outside GitHub.
- Part 2 (Terraform + Kubernetes) and Part 3 (the Visual Semantic Translator / RTL Auto-Flipper product) are the next roadmap phases and aren't started yet.
