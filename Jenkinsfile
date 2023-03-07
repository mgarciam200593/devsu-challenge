pipeline {
    agent any
    triggers {
        pollSCM '* * * * *'
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
                sh 'cd docker/ && docker build -t public.ecr.aws/t1c2g3k3/test-devsu:0.0.1 .'
            }
        }
        stage('Test'){
            steps {
                echo 'Testing Flask API'
                sh 'docker run --name test public.ecr.aws/t1c2g3k3/test-devsu:0.0.1 sh -c "pylint src/app.py ; pytest test.py"'
                sh 'docker stop test'
                sh 'docker rm test'
            }
        }
        stage('Push to repository'){
            steps {
                echo 'Push to ECR Repository'
                sh 'aws ecr-public get-login-password --region us-east-1 | docker login --username AWS --password-stdin public.ecr.aws/t1c2g3k3'
                sh 'docker push public.ecr.aws/t1c2g3k3/test-devsu:0.0.1'
            }
        }
        stage('Branch Test'){
            steps {
                sh 'echo $GIT_BRANCH'
                script {
                    if (env.BRANCH_NAME == 'main'){
                        echo 'main branch'
                    }
                    else {
                        echo 'dev branch'
                    }
                }
            }
        }
    }
}