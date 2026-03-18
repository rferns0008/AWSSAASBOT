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
                    // 1. Install unzip and force-fix the tool paths
                    sh 'sudo -n apt-get update && sudo -n apt-get install -y unzip'
            
                    // 2. AWS CLI: Update existing and ensure it's in the path
                    sh '''
                        rm -rf aws awscliv2.zip
                        curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
                        unzip -qo awscliv2.zip
                        sudo -n ./aws/install --update
                        sudo -n ln -sf /usr/local/bin/aws /usr/bin/aws
                    '''

                    // 3. Kubectl: Download and force into the global path
                    sh '''
                        curl -LO "https://dl.k8s.io/release/v1.28.0/bin/linux/amd64/kubectl"
                        sudo -n install -o root -g root -m 0755 kubectl /usr/bin/kubectl
                        sudo -n ln -sf /usr/bin/kubectl /usr/local/bin/kubectl
                    '''

                    // 4. Terraform: Force install
                    sh '''
                        wget -O- https://apt.releases.hashicorp.com/gpg | sudo -n gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg --yes
                        echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo -n tee /etc/apt/sources.list.d/hashicorp.list
                        sudo -n apt-get update && sudo -n apt-get install terraform -y
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