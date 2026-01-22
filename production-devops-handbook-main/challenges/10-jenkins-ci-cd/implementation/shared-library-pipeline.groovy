// Shared Library - vars/standardPipeline.groovy
// Reusable pipeline template for all applications

def call(Map config = [:]) {
    // Default values
    def defaults = [
        agentImage: 'maven:3.8-openjdk-11',
        buildCommand: 'mvn clean package -DskipTests',
        testCommand: 'mvn test',
        sonarQubeEnabled: true,
        securityScanEnabled: true,
        slackChannel: '#builds',
        deployToStaging: true,
        deployToProduction: false,
        smokeTestsEnabled: true,
        parallelTests: true
    ]
    
    // Merge user config with defaults
    config = defaults + config
    
    pipeline {
        agent {
            kubernetes {
                yaml podTemplate(config.agentImage)
            }
        }
        
        options {
            buildDiscarder(logRotator(numToKeepStr: '10'))
            disableConcurrentBuilds()
            timeout(time: 1, unit: 'HOURS')
            timestamps()
        }
        
        environment {
            APP_NAME = config.appName ?: env.JOB_NAME.tokenize('/').last()
            BUILD_VERSION = "${env.BUILD_NUMBER}-${getGitCommitShort()}"
            DOCKER_REGISTRY = 'docker.company.com'
        }
        
        stages {
            stage('Initialize') {
                steps {
                    script {
                        printBanner()
                        validateConfig(config)
                        notifyBuildStart(config.slackChannel)
                    }
                }
            }
            
            stage('Checkout') {
                steps {
                    checkout scm
                    script {
                        loadBuildInfo()
                    }
                }
            }
            
            stage('Build') {
                steps {
                    container('builder') {
                        script {
                            measureStage('build') {
                                sh config.buildCommand
                                archiveArtifacts artifacts: '**/target/*.jar', fingerprint: true
                            }
                        }
                    }
                }
            }
            
            stage('Test & Quality') {
                when {
                    expression { config.parallelTests }
                }
                parallel {
                    stage('Unit Tests') {
                        steps {
                            container('builder') {
                                script {
                                    measureStage('unit-tests') {
                                        sh config.testCommand
                                    }
                                }
                            }
                        }
                        post {
                            always {
                                junit '**/target/surefire-reports/**/*.xml'
                                publishCoverage adapters: [jacocoAdapter('**/target/site/jacoco/jacoco.xml')]
                            }
                        }
                    }
                    
                    stage('Security Scan') {
                        when {
                            expression { config.securityScanEnabled }
                        }
                        steps {
                            container('builder') {
                                script {
                                    measureStage('security-scan') {
                                        dependencyCheck()
                                    }
                                }
                            }
                        }
                    }
                    
                    stage('SonarQube') {
                        when {
                            expression { config.sonarQubeEnabled }
                        }
                        steps {
                            container('builder') {
                                script {
                                    measureStage('sonarqube') {
                                        runSonarAnalysis(config.appName)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            stage('Quality Gate') {
                when {
                    expression { config.sonarQubeEnabled }
                }
                steps {
                    script {
                        waitForQualityGate abortPipeline: true
                    }
                }
            }
            
            stage('Build & Push Image') {
                steps {
                    container('docker') {
                        script {
                            measureStage('docker-build') {
                                buildAndPushDockerImage(
                                    imageName: env.APP_NAME,
                                    imageTag: env.BUILD_VERSION,
                                    dockerfile: config.dockerfile ?: 'Dockerfile'
                                )
                            }
                        }
                    }
                }
            }
            
            stage('Deploy to Staging') {
                when {
                    allOf {
                        expression { config.deployToStaging }
                        branch 'develop'
                    }
                }
                steps {
                    container('kubectl') {
                        script {
                            measureStage('deploy-staging') {
                                deployToK8s(
                                    environment: 'staging',
                                    version: env.BUILD_VERSION,
                                    namespace: "${env.APP_NAME}-staging"
                                )
                            }
                        }
                    }
                }
            }
            
            stage('Smoke Tests') {
                when {
                    allOf {
                        expression { config.smokeTestsEnabled }
                        expression { config.deployToStaging }
                        branch 'develop'
                    }
                }
                steps {
                    script {
                        measureStage('smoke-tests') {
                            runSmokeTests(
                                environment: 'staging',
                                timeout: 300
                            )
                        }
                    }
                }
            }
            
            stage('Production Approval') {
                when {
                    allOf {
                        expression { config.deployToProduction }
                        branch 'main'
                    }
                }
                steps {
                    script {
                        def approvers = config.approvers ?: ['tech-lead', 'sre-team']
                        input(
                            message: "Deploy ${env.APP_NAME}:${env.BUILD_VERSION} to Production?",
                            submitter: approvers.join(','),
                            parameters: [
                                choice(
                                    name: 'DEPLOYMENT_STRATEGY',
                                    choices: ['blue-green', 'canary', 'rolling'],
                                    description: 'Deployment strategy'
                                )
                            ]
                        )
                    }
                }
            }
            
            stage('Deploy to Production') {
                when {
                    allOf {
                        expression { config.deployToProduction }
                        branch 'main'
                    }
                }
                steps {
                    container('kubectl') {
                        script {
                            measureStage('deploy-production') {
                                deployToProduction(
                                    appName: env.APP_NAME,
                                    version: env.BUILD_VERSION,
                                    strategy: env.DEPLOYMENT_STRATEGY ?: 'rolling'
                                )
                            }
                        }
                    }
                }
            }
        }
        
        post {
            always {
                script {
                    recordBuildMetrics()
                    cleanWs()
                }
            }
            
            success {
                script {
                    notifySuccess(config.slackChannel)
                }
            }
            
            failure {
                script {
                    notifyFailure(config.slackChannel)
                }
            }
        }
    }
}

// ============================================================================
// Helper Functions
// ============================================================================

def podTemplate(String image) {
    return """
apiVersion: v1
kind: Pod
metadata:
  labels:
    jenkins: agent
spec:
  serviceAccountName: jenkins-agent
  containers:
  - name: builder
    image: ${image}
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

def printBanner() {
    echo """
    ╔═══════════════════════════════════════╗
    ║   Jenkins Shared Pipeline v2.0        ║
    ║   Build: ${env.BUILD_NUMBER}                       ║
    ║   Branch: ${env.GIT_BRANCH}                  ║
    ╚═══════════════════════════════════════╝
    """
}

def validateConfig(Map config) {
    if (!config.appName && !env.JOB_NAME) {
        error("appName must be specified")
    }
}

def getGitCommitShort() {
    return sh(
        script: "git rev-parse --short HEAD",
        returnStdout: true
    ).trim()
}

def loadBuildInfo() {
    env.GIT_COMMIT_SHORT = getGitCommitShort()
    env.GIT_AUTHOR = sh(
        script: "git log -1 --pretty=format:'%an'",
        returnStdout: true
    ).trim()
    env.GIT_MESSAGE = sh(
        script: "git log -1 --pretty=format:'%s'",
        returnStdout: true
    ).trim()
}

def measureStage(String stageName, Closure body) {
    def startTime = System.currentTimeMillis()
    def success = true
    
    try {
        body()
    } catch (Exception e) {
        success = false
        throw e
    } finally {
        def duration = (System.currentTimeMillis() - startTime) / 1000
        
        // Send metrics to Prometheus
        sh """
            echo "jenkins_stage_duration_seconds{job=\\"${env.JOB_NAME}\\",stage=\\"${stageName}\\"} ${duration}" | \
            curl -s --data-binary @- http://pushgateway.monitoring:9091/metrics/job/jenkins || true
            
            echo "jenkins_stage_status{job=\\"${env.JOB_NAME}\\",stage=\\"${stageName}\\"} ${success ? 1 : 0}" | \
            curl -s --data-binary @- http://pushgateway.monitoring:9091/metrics/job/jenkins || true
        """
    }
}

def dependencyCheck() {
    sh 'mvn dependency-check:check -B'
    publishHTML(target: [
        reportDir: 'target/dependency-check-report',
        reportFiles: 'dependency-check-report.html',
        reportName: 'Dependency Check Report',
        keepAll: true
    ])
}

def runSonarAnalysis(String projectKey) {
    withSonarQubeEnv('SonarQube') {
        sh """
            mvn sonar:sonar \
                -Dsonar.projectKey=${projectKey} \
                -Dsonar.projectVersion=${env.BUILD_VERSION} \
                -B
        """
    }
}

def buildAndPushDockerImage(Map params) {
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
        sh """
            docker login -u \${DOCKER_USER} -p \${DOCKER_PASS} ${env.DOCKER_REGISTRY}
            docker build -f ${params.dockerfile} -t ${env.DOCKER_REGISTRY}/${params.imageName}:${params.imageTag} .
            docker tag ${env.DOCKER_REGISTRY}/${params.imageName}:${params.imageTag} \
                       ${env.DOCKER_REGISTRY}/${params.imageName}:latest
            docker push ${env.DOCKER_REGISTRY}/${params.imageName}:${params.imageTag}
            docker push ${env.DOCKER_REGISTRY}/${params.imageName}:latest
        """
    }
}

def deployToK8s(Map params) {
    sh """
        kubectl set image deployment/${params.environment}-deployment \
            app=${env.DOCKER_REGISTRY}/${env.APP_NAME}:${params.version} \
            -n ${params.namespace}
        
        kubectl rollout status deployment/${params.environment}-deployment \
            -n ${params.namespace} \
            --timeout=5m
    """
}

def runSmokeTests(Map params) {
    timeout(time: params.timeout, unit: 'SECONDS') {
        sh """
            curl -f -m 10 https://${env.APP_NAME}-${params.environment}.company.com/health || exit 1
            echo "Smoke tests passed"
        """
    }
}

def deployToProduction(Map params) {
    switch(params.strategy) {
        case 'blue-green':
            blueGreenDeploy(params.appName, params.version)
            break
        case 'canary':
            canaryDeploy(params.appName, params.version)
            break
        case 'rolling':
            rollingDeploy(params.appName, params.version)
            break
        default:
            error("Unknown deployment strategy: ${params.strategy}")
    }
}

def blueGreenDeploy(String appName, String version) {
    // Implementation in separate file
    load 'vars/blueGreenDeploy.groovy'
}

def canaryDeploy(String appName, String version) {
    // Implementation in separate file
    load 'vars/canaryDeploy.groovy'
}

def rollingDeploy(String appName, String version) {
    sh """
        kubectl set image deployment/production-deployment \
            app=${env.DOCKER_REGISTRY}/${appName}:${version} \
            -n ${appName}-production
        
        kubectl rollout status deployment/production-deployment \
            -n ${appName}-production \
            --timeout=10m
    """
}

def recordBuildMetrics() {
    def duration = currentBuild.duration / 1000
    def status = currentBuild.result ?: 'SUCCESS'
    
    sh """
        echo "jenkins_build_duration_seconds{job=\\"${env.JOB_NAME}\\"} ${duration}" | \
        curl -s --data-binary @- http://pushgateway.monitoring:9091/metrics/job/jenkins || true
        
        echo "jenkins_build_result{job=\\"${env.JOB_NAME}\\",result=\\"${status}\\"} 1" | \
        curl -s --data-binary @- http://pushgateway.monitoring:9091/metrics/job/jenkins || true
    """
}

def notifyBuildStart(String channel) {
    slackSend(
        channel: channel,
        color: '#439FE0',
        message: "🚀 Build Started: ${env.JOB_NAME} #${env.BUILD_NUMBER}"
    )
}

def notifySuccess(String channel) {
    slackSend(
        channel: channel,
        color: 'good',
        message: """
            ✅ Build Successful
            Job: ${env.JOB_NAME}
            Build: #${env.BUILD_NUMBER}
            Version: ${env.BUILD_VERSION}
            Author: ${env.GIT_AUTHOR}
            Duration: ${currentBuild.durationString}
            <${env.BUILD_URL}|View Build>
        """.stripIndent()
    )
}

def notifyFailure(String channel) {
    slackSend(
        channel: channel,
        color: 'danger',
        message: """
            ❌ Build Failed
            Job: ${env.JOB_NAME}
            Build: #${env.BUILD_NUMBER}
            Author: ${env.GIT_AUTHOR}
            <${env.BUILD_URL}console|View Logs>
            @here Please investigate!
        """.stripIndent()
    )
}
