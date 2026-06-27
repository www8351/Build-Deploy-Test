# Build & Deploy & Test

A small DevOps lab: two interactive **Labs** and six **Jenkins Jobs** that build, deploy and
test with Docker — wired together as a Jenkins delivery pipeline. The repo was built **one
commit per step** so the git history reads as a step-by-step walkthrough.

> Scripts target a **Linux Jenkins agent** (they use `useradd`, a package manager and
> `docker`). Install scripts auto-detect `apt-get`, `dnf` or `yum`, so they run on
> Debian/Ubuntu **and** RHEL/CentOS.

## Repo layout

```
.
├── labs/
│   ├── lab1_menu.sh          # LAB 1 - bash menu
│   ├── lab2_menu.py          # LAB 2 - python menu
│   └── lab2_helper.sh        # LAB 2 - bash read-side helper
├── jobs/
│   ├── job1_users_tar.sh     # user + 5 files + tar
│   ├── job2_docker_nginx.sh  # pull/run nginx on :8351 + curl
│   ├── job3_containers_log.sh# dump container ID/Image/Name/IP -> Log.txt
│   ├── job4_pull_remote.sh   # pull an image on a remote host over SSH
│   ├── job5_deploy3_ips.sh   # run 3 containers + print their IPs
│   └── job6_send_mail.sh     # "all good" mail at end of pipeline
├── .gitattributes            # force LF on scripts (Linux agent)
└── .gitignore                # only README.md is tracked among *.md
```

## Quick start (run locally on a Linux box / agent)

```bash
git clone https://github.com/www8351/build-deploy-test.git
cd build-deploy-test
chmod +x labs/*.sh jobs/*.sh

# Labs (interactive menus)
./labs/lab1_menu.sh
python3 labs/lab2_menu.py
./labs/lab2_helper.sh

# Jobs (most take parameters via environment variables)
USER_NAME=tester1            ./jobs/job1_users_tar.sh
HOST_PORT=8351               ./jobs/job2_docker_nginx.sh
                             ./jobs/job3_containers_log.sh
REMOTE_HOST=10.0.0.5 IMAGE=nginx ./jobs/job4_pull_remote.sh
COUNT=3 IMAGE=nginx          ./jobs/job5_deploy3_ips.sh
RECIPIENT=you@example.com    ./jobs/job6_send_mail.sh
```

## The Labs

**LAB 1 — `labs/lab1_menu.sh`** (bash menu)
1. Create a new directory in `~/Desktop/`
2. Create a new user (by input)
3. Install `curl` & `tcpdump`

**LAB 2 — `labs/lab2_menu.py`** (python menu) + **`labs/lab2_helper.sh`** (bash)
- Python: create files in a folder · run Java installation · append a line to `Log.txt`
- Bash: list a folder · show `java -version` · print `Log.txt`

## The Jobs (Jenkins build steps)

| Job | Script | What it does | Parameters |
|-----|--------|--------------|------------|
| 1 | `job1_users_tar.sh` | create user, 5 files, `tar` them to `zipfile.tgz` | `USER_NAME` |
| 2 | `job2_docker_nginx.sh` | pull nginx, run on host `:8351`, `curl` it | `HOST_PORT` |
| 3 | `job3_containers_log.sh` | write each container's ID/Image/Name/IP to `Log.txt` | — |
| 4 | `job4_pull_remote.sh` | `ssh` to a remote host and `docker pull` an image | `REMOTE_HOST`, `REMOTE_USER`, `IMAGE` |
| 5 | `job5_deploy3_ips.sh` | deploy 3 containers, print their IPs | `COUNT`, `IMAGE` |
| 6 | `job6_send_mail.sh` | send an "all good" mail | `RECIPIENT`, `SUBJECT`, `BODY` |

## Jenkins setup

### 1. Install Jenkins
Install Jenkins + a JDK on the controller, start the service, unlock with the initial admin
password, then install suggested plugins.

### 2. Let the `jenkins` user run the job commands
Several jobs need `sudo` (useradd, package installs, docker). Grant it with `visudo`:

```bash
sudo visudo
# add a line:
jenkins ALL=(ALL) NOPASSWD: ALL          # lab/demo scope; tighten for production
# and let jenkins use docker:
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins
```

### 3. Required plugins
- **Parameterized Trigger** — pass parameters and chain one job into the next
- **Git / GitHub** — clone this repo into each job
- **Delivery Pipeline** — visualize Job 1 → … → Job 6 as a pipeline

### 4. Build the pipeline
Create one freestyle job per script. In each:
- **Source Code Management → Git**: `https://github.com/www8351/build-deploy-test.git`
- **Build → Execute shell**: `bash jobs/jobN_*.sh`
- **Post-build → Trigger parameterized build on other projects**: the next job, passing
  parameters (e.g. `REMOTE_HOST`, `RECIPIENT`).

Chain: **Job1 → Job2 → Job3 → Job4 → Job5 → Job6**. Add all six to a **Delivery Pipeline**
view to watch the flow. Job 6 is the final "all good" notification — in production use the
**Editable Email Notification** (email-ext) post-build step with your SMTP server instead of
the CLI `mail` fallback.

## Notes
- `.gitignore` keeps the repo clean: every `*.md` is ignored except this `README.md`. Local
  lifecycle files (`STATUS.md`, `PROGRESS.md`, `DECISIONS.md`, `CLAUDE_MEMORY.md`) live on
  disk but are never pushed.
- `.gitattributes` forces LF endings on `*.sh`/`*.py` so the Linux agent never chokes on CRLF.
