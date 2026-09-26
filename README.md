# Account-wide GitHub Actions cleanup

This repository discovers every repository owned by your personal GitHub account, lists repositories containing GitHub Actions resources, and removes old resources on a daily schedule.

## Repository layout

- `.github/workflows/` contains the scheduled and manually dispatched GitHub Actions workflow. The job pins `ubuntu-26.04` and uses `actions/checkout@v7` with the Node.js 24 runtime.
- `sh/` contains executable shell helpers. Shell files use descriptive, hyphenated names ending in `.sh`, matching the convention used by the LPIC lab repositories.
- `test/` contains all local tests and GitHub CLI fixtures for scripts in `sh/`. `cleanup-actions-test.sh` checks every resource scope with mocked repository data, while `empty-discovery-test.sh` verifies the clear failure produced when no repositories are visible. The tests never contact GitHub and never delete Actions resources.
- `Makefile` provides dotted, namespaced commands with short aliases and categorized help.

## Resources supported

The `resources` workflow parameter supports:

- `all`: artifacts, caches, and completed workflow runs (run deletion includes its logs)
- `workflow-runs`: completed workflow runs and their logs
- `run-logs`: logs only, while preserving workflow-run history
- `artifacts`: uploaded workflow artifacts
- `caches`: Actions caches, based on their last-access time

The scheduled run selects `all`, removes resources older than one day, skips archived repositories, and performs real deletion. Manual runs default to dry-run mode.

## Required token

The standard `GITHUB_TOKEN` is limited to this repository, so the workflow needs a personal access token:

1. Open **GitHub → Settings → Developer settings → Personal access tokens → Fine-grained tokens**.
2. Create a token owned by your personal account.
3. Under **Repository access**, choose **All repositories**.
4. Under **Repository permissions**, grant **Actions: Read and write**. Metadata read access is added automatically.
5. In this repository, open **Settings → Secrets and variables → Actions → New repository secret**.
6. Name the secret `ACTIONS_ADMIN_TOKEN` and paste the token value.

A classic personal access token with the `repo` scope also works, but it grants broader access than necessary.

## Make commands

Run `make` or `make help` to display the categorized command list. The naming follows the other LPIC projects: a dotted namespace describes the operation, and common commands have short aliases.

| Command | Alias | Purpose |
|---|---:|---|
| `make check` | `make c` | Check shell syntax |
| `make test` | `make t` | Run the local mocked smoke tests |
| `make gh.login` | `make gl` | Authenticate GitHub CLI |
| `make gh.check` | `make gc` | Verify authentication and repository access |
| `make gh.secret` | `make gs` | Upload the Actions administration token |
| `make cleanup.dry.run` | `make cdr` | Dispatch a safe dry run |
| `make cleanup.run CONFIRM=delete` | `make cr CONFIRM=delete` | Dispatch real deletion |
| `make cleanup.watch` | `make cw` | Watch the latest cleanup run |
| `make cleanup.logs` | `make cl` | Display logs from the latest cleanup run |

Install [GitHub CLI](https://cli.github.com/) and GNU Make, then authenticate and verify access:

```bash
make gh.login
make gh.check
```

Upload or replace the required repository secret without placing its value in the command line:

```bash
cat <<EOF > .env
ACTIONS_ADMIN_TOKEN=YOUR_ACTIONS_ADMIN_TOKEN
EOF
```
```bash
make gh.secret
```

Run the local tests, then start safely with a workflow dry run:

```bash
make test
```
```bash
make cleanup.dry.run
make cleanup.watch
make cleanup.logs
```

Change the selected resources, retention period, or exclusions with Make variables:

```bash
make cleanup.dry.run RESOURCE_SCOPE=artifacts RETENTION_DAYS=7
make cleanup.dry.run EXCLUDED_REPOSITORIES="important-repo,anunca/another-repo"
```

Real deletion requires explicit confirmation:

```bash
make cleanup.run CONFIRM=delete
```

The configurable Make variables are `REPO`, `WORKFLOW`, `RESOURCE_SCOPE`, `RETENTION_DAYS`, `INCLUDE_ARCHIVED`, and `EXCLUDED_REPOSITORIES`.

## Run from GitHub

1. Open the repository's **Actions** tab.
2. Select **Clean GitHub Actions resources**.
3. Choose **Run workflow**.
4. Keep `dry_run` enabled and review the job summary.
5. Run it again with `dry_run` disabled when the matches look correct.

The daily schedule runs at 03:17 UTC. Change the cron expression in `.github/workflows/cleanup-actions.yml` if another time is preferable.

## Safety controls

- Only repositories owned by the token's user are processed.
- Repository discovery fails explicitly if the token returns no repositories.
- In-progress and queued workflow runs are never deleted.
- Archived repositories are skipped by default.
- `excluded_repositories` accepts comma-separated names such as `important-repo,owner/other-repo`.
- Real deletion through Make requires `CONFIRM=delete`.
- Local tests mock `gh` and cannot delete GitHub resources.
- A single concurrent cleanup is allowed, preventing overlapping deletion jobs.
