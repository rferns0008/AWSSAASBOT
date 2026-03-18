pipeline {
    agent any

    environment {
        AWS_ACCOUNT_ID  = '078083578991'
        AWS_REGION      = 'ap-south-1'
        ECR_URL         = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
        IMAGE_NAME      = "chatbot-app"
        CLUSTER_NAME    = 'secure-eks-testing'
        S3_BUCKET       = "frontend-assets-rferns-0009.xyz"
    }

    triggers {
        githubPush() // This enables the 'GitHub hook trigger' automatically
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Security: K8s Secret') {
            steps {
                withCredentials([string(credentialsId: 'OPENAI_API_KEY', variable: 'OPENAI_KEY')]) {
                    sh """
                    # 1. Ensure AWS CLI is installed
                    if ! command -v aws &> /dev/null; then
                        echo "AWS CLI not found. Installing..."
                        curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
                        unzip -q awscliv2.zip
                        sudo ./aws/install --update
                        rm -rf aws awscliv2.zip
                    fi

                    # 2. Ensure kubectl is installed
                    if ! command -v kubectl &> /dev/null; then
                        echo "kubectl not found. Installing..."
                        curl -LO "https://dl.k8s.io/release/\$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
                        chmod +x kubectl
                        sudo mv kubectl /usr/local/bin/
                    fi

                    # 3. Update Kubeconfig
                    aws eks update-kubeconfig --region ap-south-1 --name ${CLUSTER_NAME}

                    # 4. Inject Secrets
                    kubectl create namespace chatbot-production --dry-run=client -o yaml | kubectl apply -f -
                    kubectl create secret generic openai-credentials \
                     --from-literal=OPENAI_API_KEY=${OPENAI_KEY} \
                    -n chatbot-production \
                    --dry-run=client -o yaml | kubectl apply -f -
                    """
                }
            }
        }

        stage('Docker Build & Push') {
            steps {
                script {
                    // Use the ECR URI from your AWS Console
                    def ecrRepo = "078083578991.dkr.ecr.ap-south-1.amazonaws.com/flask-chatbot"
            
                    // 1. Authenticate Docker to ECR
                    sh "aws ecr get-login-password --region ap-south-1 | docker login --username AWS --password-stdin ${ecrRepo}"
            
                    // 2. Build with --no-cache to ensure the 'httpx' fix is actually installed
                    sh "docker build --no-cache -t ${ecrRepo}:latest ."
            
                    // 3. Push the new image
                    sh "docker push ${ecrRepo}:latest"
            
                    // 4. Force Kubernetes to pull the new 'latest' image immediately
                    sh "kubectl rollout restart deployment flask-chatbot -n chatbot-production"
                }
            }
        }

        stage('Deploy to EKS & Configure DNS') {
            steps {
                script {
                    // 1. Ensure Terraform is installed on the Jenkins agent
                    sh '''
                        if ! command -v terraform &> /dev/null; then
                            echo "Terraform not found. Installing..."
                            # Add --yes to gpg to skip overwrite prompts
                            wget -qO- https://apt.releases.hashicorp.com/gpg | sudo gpg --yes --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
                            echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
                            sudo apt update && sudo apt-get install terraform -y
                        else
                            echo "Terraform already installed at $(command -v terraform)"
                        fi
                    '''

                    // 2. Restart Controller & Apply Manifests
                    sh 'kubectl rollout restart deployment aws-load-balancer-controller -n kube-system'
                    sh 'kubectl apply -f deployment.yml'
                    sh "kubectl rollout restart deployment flask-chatbot -n chatbot-production"

                    // 3. Wait for ALB and extract URL cleanly
                    // Note the >&2 on the echo command - this prevents it from poisoning the variable
                    env.ALB_HOSTNAME = sh(script: '''
                        HOSTNAME=""
                        while [ -z "$HOSTNAME" ]; do
                            echo "Waiting for AWS to provision the ALB..." >&2
                            sleep 15
                            HOSTNAME=$(kubectl get ingress chatbot-ingress -n chatbot-production -o jsonpath="{.status.loadBalancer.ingress[0].hostname}")
                        done
                        echo "$HOSTNAME"
                    ''', returnStdout: true).trim()

                    echo "Successfully retrieved ALB Address: ${env.ALB_HOSTNAME}"

                    // 4. Run Terraform from the workspace root (where main.tf is)
                    // Ensure you init first, just in case the agent workspace is clean
                    sh '''
                        terraform init
                        terraform apply -var="alb_dns_name=${ALB_HOSTNAME}" -auto-approve
                    '''
                }
            }
        }

        stage('Frontend: Sync S3') {
            steps {
                script {
                    // Sync the root (.) but only include web assets
                    sh """
                    aws s3 sync . s3://frontend-assets-rferns-0009.xyz/ \
                        --exclude "*" \
                        --include "*.html" \
                        --include "*.css" \
                        --include "*.js" \
                        --include "images/*" \
                        --delete
                    """
                }
            }
        }
    }
}