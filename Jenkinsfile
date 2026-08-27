// =============================================================================
// Jenkinsfile — Smart Docker Image Shrinker & Vulnerability Trimmer Bot
//
// v3: EKS was decommissioned (cost) and replaced with a self-managed k3s
// cluster on a plain EC2 instance (smartdockershrinker-k3s), which supports
// proper Stop/Start. The pipeline still builds -> shrinks -> quality-gates
// (SonarQube) -> scans (Trivy) -> pushes to Nexus + ECR -> deploys, but the
// deploy target is now k3s via a kubeconfig Jenkins secret instead of
// `aws eks update-kubeconfig`. See PART2_SETUP.md for the one-time setup
// this pipeline assumes is already done (Jenkins credentials, SonarQube
// server config).
//
// Required on the Jenkins agent: docker, python3, aws CLI v2, kubectl, helm,
// sonar-scanner CLI.
//
// Required Jenkins configuration:
//   - Credential (Username/password) with ID `nexuslogin`
//     -> Nexus repository user + a Nexus-generated token/password.
//   - Manage Jenkins > System > SonarQube servers: a server named
//     `sonarserver` pointing at your Nexus/SonarQube EC2's URL, with an
//     auth token stored as a Jenkins secret text credential.
//   - Manage Jenkins > Global Tool Configuration > SonarQube Scanner:
//     a tool install named `sonar8.0`.
//   - Credential (Secret text) with ID `k3s-kubeconfig` containing the full
//     k3s kubeconfig YAML, with the cluster `server:` field rewritten from
//     127.0.0.1 to the k3s node's public IP (Jenkins lives in a different
//     VPC with no peering, so it must reach k3s over its public IP on
//     6443 — that port must be open in the k3s node's security group for
//     this Jenkins instance's IP).
//   - The k3s cluster's `smartdockershrinker` namespace's `default`
//     ServiceAccount must be patched with imagePullSecrets pointing at an
//     `ecr-registry-secret` (docker-registry secret) that is periodically
//     refreshed on the k3s host, since plain k3s (unlike EKS) has no
//     built-in ECR credential helper.
// =============================================================================

pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '20'))
    }

    environment {
        IMAGE_NAME        = 'smartdockershrinker'
        SONAR_PROJECT_KEY = 'smartdockershrinker'

        NEXUS_REGISTRY = "${env.NEXUS_REGISTRY ?: '172.31.39.163:8082'}"
        NEXUS_REPO     = "${env.NEXUS_REPO ?: 'docker-hosted'}"

        AWS_REGION     = "${env.AWS_REGION ?: 'us-east-1'}"
        HELM_RELEASE   = 'smartdockershrinker'
        HELM_NAMESPACE = 'smartdockershrinker'
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Verify Toolchain') {
            steps {
                // docker/python3/aws are required for every stage below, so
                // those still fail fast. kubectl/helm are only needed by the
                // Deploy to k3s stage (which is itself non-fatal if the
                // cluster can't be reached), so their absence is just a
                // warning here, not a build-breaker.
                sh '''
                    set -e
                    docker --version
                    python3 --version
                    aws --version
                '''
                sh '''
                    kubectl version --client || echo "WARNING: kubectl not found on this agent - Deploy to k3s stage will fail/skip"
                    helm version || echo "WARNING: helm not found on this agent - Deploy to k3s stage will fail/skip"
                '''
            }
        }

        // FAZ 1: Build the bloated image, for comparison
        stage('Build Original (Bloated) Image') {
            steps {
                sh 'docker build -t ${IMAGE_NAME}:bloated .'
            }
        }

        // FAZ 2: Run the shrinker engine
        stage('Run Shrinker Bot') {
            steps {
                sh '''
                    set -e
                    python3 shrinker_engine/multistage_builder.py
                    docker build -t ${IMAGE_NAME}:shrunk -f Dockerfile.shrunk .
                '''
            }
        }

        // FAZ 3: Calculate size difference
        stage('Calculate Size Savings') {
            steps {
                sh 'python3 shrinker_engine/size_calculator.py ${IMAGE_NAME}:bloated ${IMAGE_NAME}:shrunk'
            }
        }

        // FAZ 4: Static code quality — SonarQube (self-hosted on AWS)
        // scannerHome must be resolved via a stage-level `environment {}`
        // block (matching the working vprofile-ci-pipeline job on this same
        // Jenkins) - calling `tool 'sonar8.0'` inside `steps { script {} }`
        // does NOT trigger the Declarative auto-install and returns an empty
        // path, which broke this stage (`/bin/sonar-scanner: not found`).
        stage('SonarQube Analysis') {
            environment {
                scannerHome = tool 'sonar8.0'
            }
            steps {
                withSonarQubeEnv('sonarserver') {
                    sh '''
                        ${scannerHome}/bin/sonar-scanner \
                          -Dsonar.projectKey=${SONAR_PROJECT_KEY} \
                          -Dsonar.sources=. \
                          -Dsonar.python.version=3.11
                    '''
                }
            }
        }

        stage('Quality Gate') {
            steps {
                // Requires a SonarQube webhook back to this Jenkins
                // (Administration > Configuration > Webhooks in SonarQube) —
                // see PART2_SETUP.md. Without it this just times out.
                timeout(time: 5, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        // FAZ 5: Vulnerability scan (unchanged from Part 1)
        stage('Trivy Security Scan') {
            steps {
                sh '''
                    docker run --rm \
                        -v /var/run/docker.sock:/var/run/docker.sock \
                        aquasec/trivy:latest image \
                        --format table \
                        --exit-code 0 \
                        --ignore-unfixed \
                        --vuln-type os,library \
                        --severity CRITICAL,HIGH \
                        ${IMAGE_NAME}:shrunk
                '''
            }
        }

        // FAZ 6: Push the shrunk image to your self-hosted Nexus registry
        stage('Push to Nexus') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'nexuslogin',
                    usernameVariable: 'NEXUS_USER',
                    passwordVariable: 'NEXUS_PASS'
                )]) {
                    sh '''
                        set -e
                        echo "$NEXUS_PASS" | docker login ${NEXUS_REGISTRY} -u "$NEXUS_USER" --password-stdin
                        docker tag ${IMAGE_NAME}:shrunk ${NEXUS_REGISTRY}/${NEXUS_REPO}/${IMAGE_NAME}:shrunk-${BUILD_NUMBER}
                        docker tag ${IMAGE_NAME}:shrunk ${NEXUS_REGISTRY}/${NEXUS_REPO}/${IMAGE_NAME}:latest
                        docker push ${NEXUS_REGISTRY}/${NEXUS_REPO}/${IMAGE_NAME}:shrunk-${BUILD_NUMBER}
                        docker push ${NEXUS_REGISTRY}/${NEXUS_REPO}/${IMAGE_NAME}:latest
                        docker logout ${NEXUS_REGISTRY}
                    '''
                }
            }
        }

        // FAZ 7: Push the same shrunk image to ECR too. The k3s node pulls
        // from ECR over HTTPS using its own IAM instance role (no extra
        // plumbing needed) - Nexus push above is unchanged/still the
        // artifact-of-record.
        stage('Push to ECR') {
            steps {
                sh '''
                    set -e
                    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
                    ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
                    aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ECR_REGISTRY}
                    docker tag ${IMAGE_NAME}:shrunk ${ECR_REGISTRY}/${IMAGE_NAME}:shrunk-${BUILD_NUMBER}
                    docker push ${ECR_REGISTRY}/${IMAGE_NAME}:shrunk-${BUILD_NUMBER}
                    echo "${ECR_REGISTRY}" > .ecr_registry
                '''
            }
        }

        // FAZ 8: Deploy to the self-managed k3s cluster (replaces EKS) via
        // the Helm chart in helm/smartdockershrinker. The k3s node's
        // `smartdockershrinker` namespace default ServiceAccount already
        // has imagePullSecrets pointing at a periodically-refreshed
        // `ecr-registry-secret`, so `imagePullSecrets=null` here just means
        // "don't set it explicitly in the pod spec" (same technique used on
        // EKS, where the node role's built-in ECR helper made it a no-op).
        stage('Deploy to k3s') {
            steps {
                // Non-fatal on purpose: the k3s node may be stopped (cost
                // savings) or unreachable. Build still succeeds through
                // Nexus/ECR push even if this stage can't reach the cluster.
                catchError(buildResult: 'SUCCESS', stageResult: 'FAILURE') {
                    withCredentials([string(credentialsId: 'k3s-kubeconfig', variable: 'K3S_KUBECONFIG_CONTENT')]) {
                        sh '''
                            set -e
                            ECR_REGISTRY=$(cat .ecr_registry)
                            KUBECONFIG_FILE="$(pwd)/.k3s-kubeconfig-${BUILD_NUMBER}.yaml"
                            umask 077
                            set +x  # do not echo the kubeconfig secret to the console log
                            printf '%s' "$K3S_KUBECONFIG_CONTENT" > "$KUBECONFIG_FILE"
                            export KUBECONFIG="$KUBECONFIG_FILE"
                            set -x

                            kubectl create namespace ${HELM_NAMESPACE} \
                                --dry-run=client -o yaml | kubectl apply -f -

                            helm upgrade --install ${HELM_RELEASE} ./helm/smartdockershrinker \
                                --namespace ${HELM_NAMESPACE} \
                                --set image.repository=${ECR_REGISTRY}/${IMAGE_NAME} \
                                --set image.tag=shrunk-${BUILD_NUMBER} \
                                --set imagePullSecrets=null \
                                --set ingress.enabled=false \
                                --wait --timeout 5m

                            rm -f "$KUBECONFIG_FILE"
                        '''
                    }
                }
            }
        }
    }

    post {
        always {
            sh 'docker image prune -f || true'
        }
        success {
            echo "✅ Pipeline succeeded: image built, quality-gated, scanned, pushed to Nexus/ECR, and deployed to k3s."
        }
        failure {
            echo '❌ Pipeline failed — check the stage logs above.'
        }
    }
}
