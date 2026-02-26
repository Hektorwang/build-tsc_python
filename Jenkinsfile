pipeline {
    agent any

    environment {
        // DOCKER_HOST = 'tcp://192.168.19.37:2375'
        TZ = 'Asia/Shanghai'
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '5'))
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('QEMU Init') {
            steps {
                sh '''
                docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
                docker run --privileged --rm tonistiigi/binfmt --install all || true
                '''
            }
        }

        stage('Parallel Builds by OS & Arch') {
            parallel {
                stage('Build Euler AMD64') {
                    steps {
                        sh '''
                        docker buildx inspect builder-euler-amd64 || docker buildx create --name builder-euler-amd64 --driver docker-container --use
                        docker buildx use builder-euler-amd64
                        docker buildx inspect --bootstrap

                        mkdir -p /var/jenkins_home/cache-builder-euler-amd64
                        mkdir -p ./output/euler-amd64/
                        docker buildx build \\
                          --platform linux/amd64 \\
                          --output type=local,dest=./output/euler-amd64/ \\
                          --progress plain \\
                          --no-cache=false \\
                          --cache-to=type=local,dest=/var/jenkins_home/cache-builder-euler-amd64 \\
                          --cache-from=type=local,src=/var/jenkins_home/cache-builder-euler-amd64 \\
                          --target exporter \\
                          --build-arg CACHE_BUSTER_GET_MICROMAMBA=$(date +%s) \\
                          --file Euler.dockerfile .
                        '''
                    }
                }

                stage('Build Euler ARM64') {
                    steps {
                        sh '''
                        docker buildx inspect builder-euler-arm64 || docker buildx create --name builder-euler-arm64 --driver docker-container --use
                        docker buildx use builder-euler-arm64
                        docker buildx inspect --bootstrap

                        mkdir -p /var/jenkins_home/cache-builder-euler-arm64
                        mkdir -p ./output/euler-arm64/
                        docker buildx build \\
                          --platform linux/arm64 \\
                          --output type=local,dest=./output/euler-arm64/ \\
                          --progress plain \\
                          --no-cache=false \\
                          --cache-to=type=local,dest=/var/jenkins_home/cache-builder-euler-arm64 \\
                          --cache-from=type=local,src=/var/jenkins_home/cache-builder-euler-arm64 \\
                          --target exporter \\
                          --build-arg CACHE_BUSTER_GET_MICROMAMBA=$(date +%s) \\
                          --file Euler.dockerfile .
                        '''
                    }
                }

                stage('Build RedHat AMD64') {
                    steps {
                        sh '''
                        docker buildx inspect builder-redhat-amd64 || docker buildx create --name builder-redhat-amd64 --driver docker-container --use
                        docker buildx use builder-redhat-amd64
                        docker buildx inspect --bootstrap

                        mkdir -p /var/jenkins_home/cache-builder-redhat-amd64
                        mkdir -p ./output/redhat-amd64/
                        docker buildx build \\
                          --platform linux/amd64 \\
                          --output type=local,dest=./output/redhat-amd64/ \\
                          --progress plain \\
                          --no-cache=false \\
                          --cache-to=type=local,dest=/var/jenkins_home/cache-builder-redhat-amd64 \\
                          --cache-from=type=local,src=/var/jenkins_home/cache-builder-redhat-amd64 \\
                          --target exporter \\
                          --build-arg CACHE_BUSTER_GET_MICROMAMBA=$(date +%s) \\
                          --file RedHat.dockerfile .
                        '''
                    }
                }

                stage('Build RedHat ARM64') {
                    steps {
                        sh '''
                        docker buildx inspect builder-redhat-arm64 || docker buildx create --name builder-redhat-arm64 --driver docker-container --use
                        docker buildx use builder-redhat-arm64
                        docker buildx inspect --bootstrap

                        mkdir -p /var/jenkins_home/cache-builder-redhat-arm64
                        mkdir -p ./output/redhat-arm64/
                        docker buildx build \\
                          --platform linux/arm64 \\
                          --output type=local,dest=./output/redhat-arm64/ \\
                          --progress plain \\
                          --no-cache=false \\
                          --cache-to=type=local,dest=/var/jenkins_home/cache-builder-redhat-arm64 \\
                          --cache-from=type=local,src=/var/jenkins_home/cache-builder-redhat-arm64 \\
                          --target exporter \\
                          --build-arg CACHE_BUSTER_GET_MICROMAMBA=$(date +%s) \\
                          --file RedHat.dockerfile .
                        '''
                    }
                }
            }
        }

        stage('Archive Output') {
            steps {
                archiveArtifacts artifacts: 'output/**/*', fingerprint: true
            }
        }
    }
    post {
        always {
            cleanWs()
            // 如果希望构建后清理所有 buildx builder，可以取消注释以下行
            // sh 'docker buildx rm builder-euler-amd64 || true'
            // sh 'docker buildx rm builder-euler-arm64 || true'
            // sh 'docker buildx rm builder-redhat-amd64 || true'
            // sh 'docker buildx rm builder-redhat-arm64 || true'
        }
    }
}