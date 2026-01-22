// Jenkinsfile - Declarative Pipeline for Production Application
// This pipeline demonstrates best practices for Jenkins CI/CD

@Library('shared-library@main') _

pipeline {
    agent {
        kubernetes {
            yaml """
apiVersion: v1
kind: Pod
metadata:
  labels:
    jenkins: agent
    app: ${env.JOB_NAME}
spec:
  serviceAccountName: jenkins-agent
  containers:
  - name: maven
    image: maven:3.8-openjdk-11
    command: ['sleep']
    args: ['infinity']
    resources:
      requests:
        cpu: 500m
        memory: 1Gi
      limits:
        cpu: 2
        memory: 4Gi
  - name: docker
    image: docker:20.10
    command: ['sleep']
    args: ['infinity']
    volumeMounts:
    - name: docker-sock
      mountPath: /var/run/docker.sock
  - name: kubectl
    image: bitnami/kubectl:latest
    command: ['sleep']
    args: ['infinity']
  volumes:
  - name: docker-sock
    hostPath:
      path: /var/run/docker.sock
"""
        }
    }
    
    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        disableConcurrentBuilds()
        timeout(time: 1, unit: 'HOURS')
        timestamps()
    }
    
    environment {
        APP_NAME = 'myapp'
        DOCKER_REGISTRY = 'docker.company.com'
        SONARQUBE_URL = 'https://sonar.company.com'
        ARTIFACTORY_URL = 'https://artifactory.company.com'
        VAULT_ADDR = 'https://vault.company.com'
        SLACK_CHANNEL = '#deployments'
    }
    
    stages {
        stage('Checkout') {
            steps {
                checkout scm
                script {
                    env.GIT_COMMIT_SHORT = sh(
                        script: "git rev-parse --short HEAD",
                        returnStdout: true
                    ).trim()
                    env.BUILD_VERSION = "${env.BUILD_NUMBER}-${env.GIT_COMMIT_SHORT}"
                }
            }
        }
        
        stage('Build') {
            steps {
                container('maven') {
                    script {
                        recordMetrics('build') {
                            sh '''
                                mvn clean package -DskipTests \
                                    -Drevision=${BUILD_VERSION} \
                                    -B -U
                            '''
                        }
                    }
                }
            }
        }
        
        stage('Test') {
            parallel {
                stage('Unit Tests') {
                    steps {
                        container('maven') {
                            script {
                                recordMetrics('unit-tests') {
                                    sh 'mvn test -B'
                                }
                            }
                        }
                    }
                    post {
                        always {
                            junit 'target/surefire-reports/**/*.xml'
                        }
                    }
                }
                
                stage('Integration Tests') {
                    steps {
                        container('maven') {
                            script {
                                recordMetrics('integration-tests') {
                                    sh 'mvn verify -Pintegration-tests -DskipUnitTests -B'
                                }
                            }
                        }
                    }
                    post {
                        always {
                            junit 'target/failsafe-reports/**/*.xml'
                        }
                    }
                }
                
                stage('Security Scan') {
                    steps {
                        container('maven') {
                            script {
                                recordMetrics('security-scan') {
                                    sh 'mvn dependency-check:check -B'
                                }
                            }
                        }
                    }
                    post {
                        always {
                            publishHTML(target: [
                                reportDir: 'target/dependency-check-report',
                                reportFiles: 'dependency-check-report.html',
                                reportName: 'Dependency Check Report'
                            ])
                        }
                    }
                }
            }
        }
        
        stage('Code Quality') {
            steps {
                container('maven') {
                    script {
                        recordMetrics('sonarqube') {
                            withSonarQubeEnv('SonarQube') {
                                sh '''
                                    mvn sonar:sonar \
                                        -Dsonar.projectKey=${APP_NAME} \
                                        -Dsonar.projectVersion=${BUILD_VERSION} \
                                        -B
                                '''
                            }
                        }
                    }
                }
            }
        }
        
        stage('Quality Gate') {
            steps {
                script {
                    timeout(time: 5, unit: 'MINUTES') {
                        def qg = waitForQualityGate()
                        if (qg.status != 'OK') {
                            error "Pipeline aborted due to quality gate failure: ${qg.status}"
                        }
                    }
                }
            }
        }
        
        stage('Build Docker Image') {
            steps {
                container('docker') {
                    script {
                        recordMetrics('docker-build') {
                            withVault([
                                vaultSecrets: [
                                    [
                                        path: 'secret/docker-registry',
                                        secretValues: [
                                            [envVar: 'DOCKER_USER', vaultKey: 'username'],
                                            [envVar: 'DOCKER_PASS', vaultKey: 'password']
                                        ]
                                    ]
                                ]
                            ]) {
                                sh '''
                                    docker login -u ${DOCKER_USER} -p ${DOCKER_PASS} ${DOCKER_REGISTRY}
                                    docker build -t ${DOCKER_REGISTRY}/${APP_NAME}:${BUILD_VERSION} .
                                    docker tag ${DOCKER_REGISTRY}/${APP_NAME}:${BUILD_VERSION} \
                                               ${DOCKER_REGISTRY}/${APP_NAME}:latest
                                    docker push ${DOCKER_REGISTRY}/${APP_NAME}:${BUILD_VERSION}
                                    docker push ${DOCKER_REGISTRY}/${APP_NAME}:latest
                                '''
                            }
                        }
                    }
                }
            }
        }
        
        stage('Deploy to Staging') {
            when {
                branch 'develop'
            }
            steps {
                container('kubectl') {
                    script {
                        recordMetrics('deploy-staging') {
                            deployToEnvironment('staging', env.BUILD_VERSION)
                        }
                    }
                }
            }
        }
        
        stage('Deploy to Production') {
            when {
                branch 'main'
            }
            steps {
                script {
                    def userInput = input(
                        message: 'Deploy to Production?',
                        parameters: [
                            choice(
                                name: 'DEPLOYMENT_STRATEGY',
                                choices: ['blue-green', 'rolling', 'canary'],
                                description: 'Select deployment strategy'
                            )
                        ]
                    )
                    
                    container('kubectl') {
                        recordMetrics('deploy-production') {
                            if (userInput == 'blue-green') {
                                blueGreenDeploy('production', env.BUILD_VERSION)
                            } else if (userInput == 'canary') {
                                canaryDeploy('production', env.BUILD_VERSION)
                            } else {
                                rollingDeploy('production', env.BUILD_VERSION)
                            }
                        }
                    }
                }
            }
        }
        
        stage('Smoke Tests') {
            when {
                branch 'main'
            }
            steps {
                script {
                    recordMetrics('smoke-tests') {
                        def smokeTestsPassed = runSmokeTests('production')
                        if (!smokeTestsPassed) {
                            error "Smoke tests failed - initiating rollback"
                        }
                    }
                }
            }
        }
    }
    
    post {
        always {
            cleanWs()
            script {
                recordBuildMetrics()
            }
        }
        
        success {
            slackSend(
                channel: env.SLACK_CHANNEL,
                color: 'good',
                message: """
                    ✅ Build Successful
                    Job: ${env.JOB_NAME}
                    Build: ${env.BUILD_NUMBER}
                    Version: ${env.BUILD_VERSION}
                    Branch: ${env.GIT_BRANCH}
                    Duration: ${currentBuild.durationString}
                    URL: ${env.BUILD_URL}
                """.stripIndent()
            )
        }
        
        failure {
            slackSend(
                channel: env.SLACK_CHANNEL,
                color: 'danger',
                message: """
                    ❌ Build Failed
                    Job: ${env.JOB_NAME}
                    Build: ${env.BUILD_NUMBER}
                    Branch: ${env.GIT_BRANCH}
                    URL: ${env.BUILD_URL}
                    @channel Please investigate!
                """.stripIndent()
            )
        }
        
        unstable {
            slackSend(
                channel: env.SLACK_CHANNEL,
                color: 'warning',
                message: """
                    ⚠️ Build Unstable
                    Job: ${env.JOB_NAME}
                    Build: ${env.BUILD_NUMBER}
                    URL: ${env.BUILD_URL}
                """.stripIndent()
            )
        }
    }
}

// Helper functions (defined in shared library)
def recordMetrics(String stage, Closure body) {
    def startTime = System.currentTimeMillis()
    def success = true
    
    try {
        body()
    } catch (Exception e) {
        success = false
        throw e
    } finally {
        def duration = (System.currentTimeMillis() - startTime) / 1000
        
        sh """
            echo "jenkins_stage_duration_seconds{job=\\"${env.JOB_NAME}\\",stage=\\"${stage}\\"} ${duration}" | \
            curl --data-binary @- http://pushgateway.monitoring:9091/metrics/job/jenkins
        """
    }
}
