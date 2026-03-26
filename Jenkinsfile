pipeline {
    agent any
    environment {
        REGION          = "ap-south-1"
        ECR_REPO        = "078083578991.dkr.ecr.ap-south-1.amazonaws.com/chatbot-app"
        NAMESPACE       = "chatbot-production"
        CLUSTER_NAME    = "secure-eks-testing"
        S3_BUCKET       = "frontend-assets-rferns-0009.xyz"
    }
    
    triggers {
        githubPush()
    }

    stages {
        stage('Tool Setup') {
            steps {
                script {
                    sh 'sudo -n apt-get update && sudo -n apt-get install -y unzip'
                    sh 'sudo chmod 666 /var/run/docker.sock || true'
       
                    sh '''
                        if ! command -v aws &> /dev/null; then
                            rm -rf aws awscliv2.zip
                            curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
                            unzip -qo awscliv2.zip
                            sudo -n ./aws/install --update
                            sudo -n ln -sf /usr/local/bin/aws /usr/bin/aws
                        fi
                    '''

                    sh '''
                        if ! command -v kubectl &> /dev/null; then
                            curl -LO "https://dl.k8s.io/release/v1.28.0/bin/linux/amd64/kubectl"
                            sudo -n install -o root -g root -m 0755 kubectl /usr/bin/kubectl
                            sudo -n ln -sf /usr/bin/kubectl /usr/local/bin/kubectl
                        fi
                    '''

                    sh '''
                        if ! command -v terraform &> /dev/null; then
                            wget -O- https://apt.releases.hashicorp.com/gpg | sudo -n gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg --yes
                            echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo -n tee /etc/apt/sources.list.d/hashicorp.list
                            while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do echo "Waiting for apt lock..."; sleep 2; done
                            sudo -n apt-get update
                            sudo -n apt-get install terraform -y
                        fi
                    '''
                }
            }
        }

        stage('Deploy Core Infra') {
            when {
                expression { return currentBuild.number == 1 || sh(script: "git diff --name-only HEAD^ HEAD | grep '\\.tf'", returnStatus: true) == 0 }
            }
            steps {
                script {
                    sh "terraform init -migrate-state -no-color"
                    
                    // NEW: Added the kube_prometheus_stack to the Phase 1 deployment targets
                    // This ensures Prometheus and its CRDs exist before we deploy the app
                    sh "terraform apply -target=module.vpc -target=module.eks -target=aws_acm_certificate_validation.alb_cert_validation -target=helm_release.aws_lb_controller -target=helm_release.kube_prometheus_stack -auto-approve -no-color"
                }
            }
        }
    
        stage('Backend: Push & Deploy') {
            steps {
                withCredentials([string(credentialsId: 'OPENAI_API_KEY', variable: 'OPENAI_KEY')]) {
                    script {
                        sh "aws ecr get-login-password --region ${REGION} | docker login --username AWS --password-stdin ${ECR_REPO}"
                        sh "docker build --no-cache -t ${ECR_REPO}:latest ."
                        sh "docker push ${ECR_REPO}:latest"
                
                        sh "aws eks update-kubeconfig --region ${REGION} --name ${CLUSTER_NAME}"
                        sh "kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -"
                        sh "kubectl create secret generic openai-credentials --from-literal=OPENAI_API_KEY=${OPENAI_KEY} -n ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -"
                
                        // Deploy the Chatbot and ALB Ingress
                        sh "kubectl apply -f deployment.yml -n ${NAMESPACE}"
                        
                        // NEW: Deploy the ServiceMonitor to tell Prometheus to scrape the Chatbot
                        // This must happen after Core Infra is deployed so the CRD is recognized
                        sh "kubectl apply -f monitor.yml"
                        
                        sh "kubectl rollout restart deployment flask-chatbot -n ${NAMESPACE}"
                    }
                }   
            }
        }

        stage('Deploy Edge Infra') {
            when {
                expression { return currentBuild.number == 1 || sh(script: "git diff --name-only HEAD^ HEAD | grep '\\.tf'", returnStatus: true) == 0 }
            }
            steps {
                script {
                    echo "Waiting for AWS to provision the ALB..."
                    sh '''
                        while [ -z $(kubectl get ingress flask-chatbot-ingress -n chatbot-production -o jsonpath="{.status.loadBalancer.ingress[0].hostname}" 2>/dev/null) ]; do
                            echo "ALB not ready yet, waiting 15 seconds..."
                            sleep 15
                        done
                        echo "ALB successfully provisioned!"
                    '''
                    sh "terraform apply -auto-approve -no-color"
                }
            }
        }

        stage('Sync Frontend') {
            steps {
                script {
                    sh "aws s3 sync . s3://${S3_BUCKET} --exclude '*' --include '*.html' --include '*.js' --include '*.css' --quiet"
                }
            }
        }
    }
    
    post {
        success {
            script {
                echo "Deploy Successful. Running Post-Deploy Tasks..."
                
                sh "aws cloudfront create-invalidation --distribution-id E3TBHRLHXAKRKQ --paths '/*'"
                
                echo "Running Frontend & API Health Checks..."
                sh "curl -sI https://${S3_BUCKET.replace('frontend-assets-', '')} | grep '200 OK'"
                sh "curl -sI https://api.${S3_BUCKET.replace('frontend-assets-', '')}/chat | grep -E '200 OK|405 Method Not Allowed'"
            }
        }
        failure {
            echo "Pipeline failed. Check Terraform logs or Kubernetes pod status."
        }
    }
}