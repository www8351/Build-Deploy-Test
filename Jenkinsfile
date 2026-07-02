// Declarative pipeline-as-code for build-deploy-test.
// Replaces the six chained freestyle jobs (Job1 -> ... -> Job6) from the README
// with a single versioned pipeline. String parameters are exposed to `sh` steps
// as environment variables, so each jobN script reads them exactly as before.
//
// The delivery flow (Job 1-6) always runs. The security/compliance jobs
// (Job 7,8,9,10,11,13,15,18) are OPT-IN and skipped by default, because some
// of them harden THIS agent (Job 7 rewrites sshd, Job 10 sets the firewall to
// default-DROP) or need cloud credentials. Enable one via its parameter.
//
// Requirements on the agent:
//   - Linux with bash, docker (jenkins user in the docker group) and sudo rights
//   - python3 for the Python jobs (9, 11, 18)
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

        // --- Security & Compliance (all opt-in; default = skipped) ---
        booleanParam(name: 'RUN_SSH_HARDENING', defaultValue: false, description: 'Job 7 - HARDEN THIS AGENT sshd (applies immediately, no dry run)')
        string(name: 'TRIVY_IMAGE',  defaultValue: '',    description: 'Job 8 - image to CVE-scan (empty = skip)')
        string(name: 'TRIVY_THRESHOLD', defaultValue: '0', description: 'Job 8 - max HIGH/CRITICAL vulns before failing the build')
        booleanParam(name: 'RUN_FIM', defaultValue: false, description: 'Job 9 - build FIM SHA-256 baseline of /etc,/var/spool/cron,/root/.ssh')
        booleanParam(name: 'RUN_IPTABLES', defaultValue: false, description: 'Job 10 - firewall lockdown on THIS AGENT')
        booleanParam(name: 'IPTABLES_DRY_RUN', defaultValue: true, description: 'Job 10 - only print the ruleset, do NOT apply (keep true unless you mean it)')
        string(name: 'HEALTH_URL',   defaultValue: '',    description: 'Job 11 - API URL to health-check (empty = skip)')
        string(name: 'GPG_RECIPIENT', defaultValue: '',   description: 'Job 13 - gpg recipient for encrypted pg_dump (empty = skip)')
        booleanParam(name: 'PROVISION_EC2', defaultValue: false, description: 'Job 15 - provision a hardened EC2 (needs AWS credentials on the agent)')
        string(name: 'GCP_PROJECT',  defaultValue: '',    description: 'Job 18 - GCP project id to IAM-audit (empty = skip)')
    }

    stages {
        stage('Preflight') {
            steps {
                // Wipe outputs from a previous build so archived artifacts are
                // always from this run, and fail fast on an unfit agent.
                sh '''
                    rm -f Log.txt zipfile.tgz trivy_report.json fim_baseline.db iam_audit.md
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

        // Opt-in hardening / audit / provisioning. Each child skips unless its
        // parameter is set, so a default build runs only the delivery flow.
        stage('Security & Compliance') {
            stages {
                stage('Job 7 - sshd hardening') {
                    when { expression { params.RUN_SSH_HARDENING } }
                    steps { sh 'bash jobs/job7_ssh_hardening.sh' }
                }
                stage('Job 8 - trivy CVE scan') {
                    when { expression { params.TRIVY_IMAGE?.trim() } }
                    // remap: job8 reads $IMAGE, but $IMAGE is the delivery param
                    // (nginx). Scan the operator-chosen TRIVY_IMAGE instead.
                    environment {
                        IMAGE     = "${params.TRIVY_IMAGE}"
                        THRESHOLD = "${params.TRIVY_THRESHOLD}"
                    }
                    steps { sh 'bash jobs/job8_trivy_docker_scan.sh' }
                }
                stage('Job 9 - FIM baseline') {
                    when { expression { params.RUN_FIM } }
                    steps { sh 'python3 jobs/job9_fim_baseline.py' }
                }
                stage('Job 10 - iptables lockdown') {
                    when { expression { params.RUN_IPTABLES } }
                    environment { DRY_RUN = "${params.IPTABLES_DRY_RUN ? '1' : ''}" }
                    steps { sh 'bash jobs/job10_iptables_lockdown.sh' }
                }
                stage('Job 11 - API health monitor') {
                    when { expression { params.HEALTH_URL?.trim() } }
                    steps { sh 'python3 jobs/job11_api_health_monitor.py --url "$HEALTH_URL"' }
                }
                stage('Job 13 - encrypted pg_dump') {
                    when { expression { params.GPG_RECIPIENT?.trim() } }
                    steps { sh 'bash jobs/job13_pg_dump_encrypt.sh' }
                }
                stage('Job 15 - provision EC2') {
                    when { expression { params.PROVISION_EC2 } }
                    steps { sh 'bash jobs/job15_aws_ec2_provision.sh' }
                }
                stage('Job 18 - GCP IAM audit') {
                    when { expression { params.GCP_PROJECT?.trim() } }
                    steps { sh 'python3 jobs/job18_gcp_iam_least_priv.py --project "$GCP_PROJECT" --status-file iam_audit.md' }
                }
            }
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
            archiveArtifacts artifacts: 'Log.txt, zipfile.tgz, trivy_report.json, fim_baseline.db, iam_audit.md',
                             allowEmptyArchive: true
        }
    }
}
