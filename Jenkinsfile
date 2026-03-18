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
                    // 1. Unzip is already verified as present
                    sh 'sudo -n apt-get update && sudo -n apt-get install -y unzip'
            
                    // 2. AWS CLI: Use --update to bypass "preexisting installation" errors
                    sh '''
                        if aws --version &> /dev/null; then
                            echo "AWS CLI already exists. Skipping install."
                        else
                            echo "Installing AWS CLI..."
                            rm -rf aws awscliv2.zip
                            curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
                            unzip -qo awscliv2.zip
                            sudo -n ./aws/install --update
                            rm -rf aws awscliv2.zip
                        fi
                    '''

                    // 3. Kubectl: Check and install
                    sh '''
                        if kubectl version --client &> /dev/null; then
                            echo "Kubectl already exists."
                        else
                            curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
                            sudo -n install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
                            rm kubectl
                        fi
                    '''

                    // 4. Terraform: Check and install
                    sh '''
                        if terraform version &> /dev/null; then
                            echo "Terraform already exists."
                        else
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