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
        stage('Checkout SCM') {
            steps {
                checkout scm
            }
        }

        stage('Backend: Push & Deploy') {
            steps {
                script {
                    // Restoring the specific shell-based login and build flow from March 17th
                    sh "aws ecr get-login-password --region ${REGION} | docker login --username AWS --password-stdin ${ECR_REPO}"
                    sh "docker build --no-cache -t ${ECR_REPO}:latest ."
                    sh "docker push ${ECR_REPO}:latest"
                    
                    // Kubernetes deployment logic restored to follow the push immediately
                    sh "aws eks update-kubeconfig --region ${REGION} --name ${CLUSTER_NAME}"
                    sh "kubectl apply -f deployment.yml -n ${NAMESPACE}"
                    sh "kubectl rollout restart deployment flask-chatbot -n ${NAMESPACE}"
                }
            }
        }

        stage('Deploy Infra') {
            steps {
                script {
                    // Running Terraform from the root as per your project structure
                    sh "terraform init -no-color"
                    sh "terraform apply -auto-approve -no-color"
                }
            }
        }

        stage('Frontend: Sync S3') {
            steps {
                script {
                    sh "aws s3 sync . s3://${S3_BUCKET} --exclude '*' --include '*.html' --include '*.js' --include '*.css' --quiet"
                }
            }
        }
    }
}