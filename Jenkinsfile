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
                    
                    // Docker Socket Permission Fix: Ensures app deploys work without manual SSH
                    sh 'sudo chmod 666 /var/run/docker.sock || true'
       
                    // AWS CLI: Skip if already verified in previous successful step
                    sh '''
                        if ! command -v aws &> /dev/null; then
                            rm -rf aws awscliv2.zip
                            curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
                            unzip -qo awscliv2.zip
                            sudo -n ./aws/install --update
                            sudo -n ln -sf /usr/local/bin/aws /usr/bin/aws
                        fi
                    '''

                    // Kubectl: Skip if already verified in previous successful step
                    sh '''
                        if ! command -v kubectl &> /dev/null; then
                            curl -LO "https://dl.k8s.io/release/v1.28.0/bin/linux/amd64/kubectl"
                            sudo -n install -o root -g root -m 0755 kubectl /usr/bin/kubectl
                            sudo -n ln -sf /usr/bin/kubectl /usr/local/bin/kubectl
                        fi
                    '''

                    // Terraform: Added a "Wait for Lock" to prevent the Exit Code 100
                    sh '''
                        if ! command -v terraform &> /dev/null; then
                            wget -O- https://apt.releases.hashicorp.com/gpg | sudo -n gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg --yes
                            echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo -n tee /etc/apt/sources.list.d/hashicorp.list
                    
                            # Wait for any background apt processes to finish
                            while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do echo "Waiting for apt lock..."; sleep 2; done
                    
                            sudo -n apt-get update
                            sudo -n apt-get install terraform -y
                        fi
                    '''
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

                        // Create namespace if missing
                        sh "kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -"
                
                        // Create or update the Kubernetes Secret
                        sh "kubectl create secret generic openai-credentials --from-literal=OPENAI_API_KEY=${OPENAI_KEY} -n ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -"
                
                        sh "kubectl apply -f deployment.yml -n ${NAMESPACE}"
                        sh "kubectl rollout restart deployment flask-chatbot -n ${NAMESPACE}"
                    }
                }   
            }
        }

        stage('Deploy Infra') {
            when {
                // Runs if it is the first build OR if any .tf files were modified in the commit
                expression { 
                    return currentBuild.number == 1 || 
                           sh(script: "git diff --name-only HEAD^ HEAD | grep '\\.tf'", returnStatus: true) == 0 
                }
            }
            steps {
                script {
                    sh "terraform init -migrate-state -no-color"
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