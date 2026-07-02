// Declarative pipeline-as-code for build-deploy-test.
// Replaces the six chained freestyle jobs (Job1 -> ... -> Job6) from the README
// with a single versioned pipeline. String parameters are exposed to `sh` steps
// as environment variables, so each jobN script reads them exactly as before.
//
// Requirements on the agent:
//   - Linux with bash, docker (jenkins user in the docker group) and sudo rights
//   - Timestamper plugin for the timestamps() option (part of suggested plugins)

pipeline {
    agent any   // pin to a dedicated node with: agent { label 'linux' }

    options {
        timestamps()
        disableConcurrentBuilds()
        timeout(time: 30, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '20'))
    }

    parameters {
        string(name: 'USER_NAME',   defaultValue: 'tester1', description: 'Job 1 - user to create')
        string(name: 'HOST_PORT',   defaultValue: '8351',    description: 'Job 2 - host port for nginx')
        string(name: 'REMOTE_HOST', defaultValue: '',        description: 'Job 4 - remote host for docker pull (empty = skip stage)')
        string(name: 'REMOTE_USER', defaultValue: 'root',    description: 'Job 4 - SSH user on the remote host')
        string(name: 'IMAGE',       defaultValue: 'nginx',   description: 'Jobs 4/5 - docker image')
        string(name: 'COUNT',       defaultValue: '3',       description: 'Job 5 - number of containers to deploy')
        string(name: 'RECIPIENT',   defaultValue: '',        description: 'Job 6 - mail recipient (empty = skip stage)')
        string(name: 'SUBJECT',     defaultValue: 'Pipeline finished - all good', description: 'Job 6 - mail subject')
        string(name: 'BODY',        defaultValue: 'All pipeline steps completed successfully.', description: 'Job 6 - mail body')
    }

    stages {
        stage('Preflight') {
            steps {
                // Wipe outputs from a previous build so archived artifacts are
                // always from this run, and fail fast on an unfit agent.
                sh '''
                    rm -f Log.txt zipfile.tgz
                    command -v docker >/dev/null || { echo "Agent lacks docker" >&2; exit 1; }
                    sudo -n true 2>/dev/null   || { echo "Agent lacks passwordless sudo" >&2; exit 1; }
                '''
            }
        }
        stage('Job 1 - user + files + tar') {
            steps { sh 'bash jobs/job1_users_tar.sh' }
        }
        stage('Job 2 - nginx up + curl') {
            steps { sh 'bash jobs/job2_docker_nginx.sh' }
        }
        stage('Job 3 - containers -> Log.txt') {
            steps { sh 'bash jobs/job3_containers_log.sh' }
        }
        stage('Job 4 - remote docker pull') {
            when { expression { params.REMOTE_HOST?.trim() } }
            steps { sh 'bash jobs/job4_pull_remote.sh' }
        }
        stage('Job 5 - deploy containers + IPs') {
            steps { sh 'bash jobs/job5_deploy3_ips.sh' }
        }
        stage('Job 6 - all-good mail') {
            when { expression { params.RECIPIENT?.trim() } }
            steps { sh 'bash jobs/job6_send_mail.sh' }
        }
    }

    post {
        success {
            echo 'Pipeline finished - all stages green.'
            script {
                if (!params.REMOTE_HOST?.trim()) {
                    echo 'NOTE: Job 4 remote pull SKIPPED (no REMOTE_HOST set).'
                }
                if (!params.RECIPIENT?.trim()) {
                    echo 'NOTE: Job 6 mail SKIPPED (no RECIPIENT set).'
                }
            }
        }
        failure {
            echo 'Pipeline failed - check the first red stage above.'
        }
        always {
            archiveArtifacts artifacts: 'Log.txt, zipfile.tgz', allowEmptyArchive: true
        }
    }
}
