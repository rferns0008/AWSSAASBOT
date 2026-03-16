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

        stage('Backend: Push & Deploy') {
            steps {
                script {
                    sh "aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ECR_URL}"
                    def appImage = docker.build("${ECR_URL}/${IMAGE_NAME}:${env.BUILD_NUMBER}")
                    appImage.push()
                    
                    sh "kubectl apply -f deployment.yml"
                    sh "kubectl set image deployment/flask-chatbot chatbot-container=${ECR_URL}/${IMAGE_NAME}:${env.BUILD_NUMBER} -n chatbot-production"
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