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
                    // Check for unzip, required for AWS CLI installation
                    sh 'sudo -n apt-get update && sudo -n apt-get install -y unzip'
            
                    // Install AWS CLI if missing
                    sh '''
                        if ! command -v aws &> /dev/null; then
                            curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
                            unzip -q awscliv2.zip
                            sudo -n ./aws/install
                            rm -rf aws awscliv2.zip
                        fi
                    '''
                    // Install kubectl if missing
                    sh '''
                        if ! command -v kubectl &> /dev/null; then
                            curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
                            sudo -n install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
                            rm kubectl
                        fi
                    '''
                    // Install terraform if missing
                    sh '''
                        if ! command -v terraform &> /dev/null; then
                            wget -O- https://apt.releases.hashicorp.com/gpg | sudo -n gpg --dearmor | sudo -n tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null
                            echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo -n tee /etc/apt/sources.list.d/hashicorp.list
                            sudo -n apt-get update && sudo -n apt-get install terraform -y
                        fi
                    '''
                }
            }
        }

        stage('Backend: Push & Deploy') {
            steps {
                script {
                    sh "aws ecr get-login-password --region ${REGION} | docker login --username AWS --password-stdin ${ECR_REPO}"
                    sh "docker build --no-cache -t ${ECR_REPO}:latest ."
                    sh "docker push ${ECR_REPO}:latest"
                    
                    sh "aws eks update-kubeconfig --region ${REGION} --name ${CLUSTER_NAME}"
                    sh "kubectl apply -f deployment.yml -n ${NAMESPACE}"
                    sh "kubectl rollout restart deployment flask-chatbot -n ${NAMESPACE}"
                }
            }
        }

        stage('Deploy Infra') {
            steps {
                script {
                    sh "terraform init -no-color"
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
}