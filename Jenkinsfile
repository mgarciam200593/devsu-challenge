pipeline {
    agent any
    environment {
        REPO_REGISTRY   = 'public.ecr.aws/t1c2g3k3'
        IMAGE_NAME      = 'test-devsu'
        IMAGE_TAG       = '0.0.2'
        CONTAINER_NAME  = 'flask-api'
    }
    stages {
        stage('Git Checkout') {
            steps {
                checkout scmGit(branches: [[name: 'main'], [name: 'dev']], extensions: [], userRemoteConfigs: [[url: 'https://github.com/mgarciam200593/devsu-challenge.git']])
            }
        }
        stage('Build') {
            steps {
                echo 'Building Flask API image'
                sh 'cd docker/ && docker build -t ${REPO_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG} .'
            }
        }
        stage('Test'){
            steps {
                echo 'Testing Flask API'
                sh 'docker run --name ${CONTAINER_NAME} ${REPO_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG} sh -c "pylint src/app.py ; pytest test.py"'
                sh 'docker stop ${CONTAINER_NAME}'
                sh 'docker rm ${CONTAINER_NAME}'
            }
        }
        stage('Push to repository'){
            steps {
                echo 'Push to ECR Repository'
                sh 'aws ecr-public get-login-password --region us-east-1 | docker login --username AWS --password-stdin ${REPO_REGISTRY}'
                sh 'docker push ${REPO_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}'
            }
        }
        stage('Deploy App'){
            steps {
                echo '${GIT_BRANCH#*/}'
                sh 'terraform -chdir="./infra/nginx" init'
                sh 'terraform -chdir="./infra/nginx" workspace new ${GIT_BRANCH#*/}  || echo "Workspace ${GIT_BRANCH#*/} already exists"'
                sh 'terraform -chdir="./infra/nginx" workspace select ${GIT_BRANCH#*/}'
                sh 'terraform -chdir="./infra/nginx" plan'
                sh 'terraform -chdir="./infra/nginx" apply -auto-approve'
                sh 'terraform -chdir="./infra/application" init'
                sh 'terraform -chdir="./infra/application" workspace new ${GIT_BRANCH#*/} || echo "Workspace ${GIT_BRANCH#*/} already exists"'
                sh 'terraform -chdir="./infra/application" workspace select ${GIT_BRANCH#*/}'
                sh 'terraform -chdir="./infra/application" plan -var="image_tag=${IMAGE_TAG}"'
                sh 'terraform -chdir="./infra/application" apply -var="image_tag=${IMAGE_TAG}" -auto-approve'
                }
            }
        }
    }
}