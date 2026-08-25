// =============================================================================
// Jenkinsfile — Smart Docker Image Shrinker & Vulnerability Trimmer Bot
//
// v2: extends the Part 1 pipeline (build -> shrink -> report -> Trivy) with
// the Part 2 stack you already run on AWS: SonarQube (code quality gate),
// Nexus (Docker registry), and an EKS cluster (deploy target) provisioned
// by infra/terraform. See PART2_SETUP.md for the one-time setup this
// pipeline assumes is already done (Jenkins credentials, SonarQube server
// config, EKS access entry for the Jenkins IAM role, ingress-nginx
// installed on the cluster).
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
//   - Jenkins EC2 instance's IAM role must be present in
//     `additional_eks_access_entries` in infra/terraform (or added later
//     via `aws eks create-access-entry`) so `aws eks update-kubeconfig`
//     actually grants kubectl/helm access.
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

        AWS_REGION       = "${env.AWS_REGION ?: 'us-east-1'}"
        EKS_CLUSTER_NAME = "${env.EKS_CLUSTER_NAME ?: 'smartdockershrinker-eks'}"
        HELM_RELEASE     = 'smartdockershrinker'
        HELM_NAMESPACE   = 'smartdockershrinker'
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
                // Deploy to EKS stage (which is itself non-fatal until the
                // cluster exists - see infra/terraform + PART2_SETUP.md), so
                // their absence is just a warning here, not a build-breaker.
                sh '''
                    set -e
                    docker --version
                    python3 --version
                    aws --version
                '''
                sh '''
                    kubectl version --client || echo "WARNING: kubectl not found on this agent - Deploy to EKS stage will fail/skip"
                    helm version || echo "WARNING: helm not found on this agent - Deploy to EKS stage will fail/skip"
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

        // FAZ 7: Push the same shrunk image to ECR too. The EKS nodes live in
        // a separate VPC from Nexus (172.31.x.x, no peering) and Nexus talks
        // plain HTTP, so pulling straight from Nexus would need VPC peering
        // *and* a containerd insecure-registry config on every node. ECR is
        // in the same account, reachable over the node's existing NAT egress,
        // HTTPS, and node roles already get ECR pull rights by default from
        // the terraform-aws-modules/eks module - no extra plumbing needed.
        // Nexus push above is unchanged/still the artifact-of-record.
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

        // FAZ 8: Deploy to EKS via the Helm chart in helm/smartdockershrinker
        // Infra itself (VPC/EKS) is NOT touched here — that stays a manual
        // `terraform apply` from your PC by design (see PART2_SETUP.md).
        stage('Deploy to EKS') {
            steps {
                // Non-fatal on purpose: the EKS cluster (infra/terraform)
                // may not be provisioned yet. Build still succeeds through
                // Nexus push even if this stage can't reach a cluster.
                catchError(buildResult: 'SUCCESS', stageResult: 'FAILURE') {
                    sh '''
                        set -e
                        ECR_REGISTRY=$(cat .ecr_registry)
                        aws eks update-kubeconfig --name ${EKS_CLUSTER_NAME} --region ${AWS_REGION}

                        kubectl create namespace ${HELM_NAMESPACE} \
                            --dry-run=client -o yaml | kubectl apply -f -

                        helm upgrade --install ${HELM_RELEASE} ./helm/smartdockershrinker \
                            --namespace ${HELM_NAMESPACE} \
                            --set image.repository=${ECR_REGISTRY}/${IMAGE_NAME} \
                            --set image.tag=shrunk-${BUILD_NUMBER} \
                            --set imagePullSecrets=null \
                            --wait --timeout 5m
                    '''
                }
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
            echo "✅ Pipeline succeeded: image built, quality-gated, scanned, pushed to Nexus, and deployed to EKS."
        }
        failure {
            echo '❌ Pipeline failed — check the stage logs above.'
        }
    }
}
