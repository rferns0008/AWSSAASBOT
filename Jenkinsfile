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
                    // 1. Ensure unzip is present for AWS CLI (Sudoers fix now allows this)
                    sh 'sudo -n apt-get update && sudo -n apt-get install -y unzip'
            
                    // 2. AWS CLI Logic: Check before install
                    sh '''
                        if ! command -v aws &> /dev/null; then
                            echo "AWS CLI not found. Installing..."
                            rm -rf aws awscliv2.zip
                            curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
                            unzip -qo awscliv2.zip
                            sudo -n ./aws/install
                            rm -rf aws awscliv2.zip
                        else
                            echo "AWS CLI already installed at $(command -v aws)"
                        fi
                    '''

                    // 3. Kubectl Logic: Check before install
                    sh '''
                        if ! command -v kubectl &> /dev/null; then
                            echo "Kubectl not found. Installing..."
                            curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
                            sudo -n install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
                            rm kubectl
                        else
                            echo "Kubectl already installed at $(command -v kubectl)"
                        fi
                    '''

                    // 4. Terraform Logic: Check before install
                    sh '''
                        if ! command -v terraform &> /dev/null; then
                            echo "Terraform not found. Installing..."
                            wget -O- https://apt.releases.hashicorp.com/gpg | sudo -n gpg --dearmor | sudo -n tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null
                            echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo -n tee /etc/apt/sources.list.d/hashicorp.list
                            sudo -n apt-get update && sudo -n apt-get install terraform -y
                        else
                            echo "Terraform already installed at $(command -v terraform)"
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