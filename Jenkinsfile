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
                    aws eks update-kubeconfig --region ${AWS_REGION} --name ${CLUSTER_NAME}
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
                    
                    sh "kubectl apply -f deployment.yaml"
                    sh "kubectl set image deployment/flask-chatbot chatbot-container=${ECR_URL}/${IMAGE_NAME}:${env.BUILD_NUMBER} -n chatbot-production"
                }
            }
        }

        stage('Frontend: Sync S3') {
            steps {
                script {
                    sh "aws s3 sync ./frontend s3://${S3_BUCKET}/ --delete"
                    // Corrected CloudFront invalidation lookup
                    def cfId = sh(script: "aws cloudfront list-distributions --query \"DistributionList.Items[?Aliases.Items[0]=='rferns-0009.xyz'].Id\" --output text", returnStdout: true).trim()
                    if (cfId != "None" && cfId != "") {
                        sh "aws cloudfront create-invalidation --distribution-id ${cfId} --paths '/*'"
                    }
                }
            }
        }
    }
}