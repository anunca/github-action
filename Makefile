.PHONY: help check test gh.login gh.check gh.secret cleanup.dry.run cleanup.run cleanup.watch cleanup.logs cleanup.run.list gh.repo.list gh.repo.run.list gh.repo.run.list.failure gh.repo.list.branch.protected gh.repo.list.settings gh.repo.apply.settings
.DEFAULT_GOAL := help

include .env.local
-include .env

export

REPO ?= anunca/github-action
WORKFLOW ?= cleanup-actions.yml
RESOURCE_SCOPE ?= all
RETENTION_DAYS ?= 1
INCLUDE_ARCHIVED ?= false
EXCLUDED_REPOSITORIES ?=

help h: ## Show help
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z0-9_. -]+:.*##/ {split($$1,a," "); printf "%-20s %s\n",a[1],$$2}' $(MAKEFILE_LIST)

##@ Project
check c: ## Check shell syntax
	@bash -n sh/cleanup-actions.sh
	@bash -n test/cleanup-actions-test.sh
	@bash -n test/empty-discovery-test.sh
	@bash -n test/bin/gh
	@echo "shell syntax looks good"

test t: check ## Run local smoke tests with a mocked GitHub CLI
	@bash test/cleanup-actions-test.sh
	@bash test/empty-discovery-test.sh

##@ GitHub CLI
gh.login gl: ## Authenticate GitHub CLI in a web browser
	@command -v gh >/dev/null || { echo "GitHub CLI (gh) is required: https://cli.github.com/" >&2; exit 1; }
	gh auth login --hostname github.com --git-protocol https --web

gh.check gc: ## Check CLI, authentication, and repository access
	@command -v gh >/dev/null || { echo "GitHub CLI (gh) is required: https://cli.github.com/" >&2; exit 1; }
	gh auth status --hostname github.com
	gh repo view "$(REPO)" >/dev/null
	@echo "GitHub CLI can access $(REPO)."

gh.secret gs: gh.check ## Upload ACTIONS_ADMIN_TOKEN as a repository secret
	@test -n "$$ACTIONS_ADMIN_TOKEN" || { echo "Set ACTIONS_ADMIN_TOKEN in the environment." >&2; exit 1; }
	@printf '%s' "$$ACTIONS_ADMIN_TOKEN" | gh secret set ACTIONS_ADMIN_TOKEN --repo "$(REPO)"
	@echo "Repository secret ACTIONS_ADMIN_TOKEN updated."

##@ Cleanup workflow
cleanup.dry.run cdr: ## Dispatch a cleanup in dry-run mode
	gh workflow run "$(WORKFLOW)" --repo "$(REPO)" \
		-f resources="$(RESOURCE_SCOPE)" \
		-f retention_days="$(RETENTION_DAYS)" \
		-f dry_run=true \
		-f include_archived="$(INCLUDE_ARCHIVED)" \
		-f excluded_repositories="$(EXCLUDED_REPOSITORIES)"
	@echo "Dry run requested. Use 'make cleanup.watch' to follow it."

cleanup.run cr: ## Dispatch a real cleanup; requires CONFIRM=delete
	@test "$(CONFIRM)" = "delete" || { echo "Deletion blocked. Re-run with CONFIRM=delete." >&2; exit 1; }
	gh workflow run "$(WORKFLOW)" --repo "$(REPO)" \
		-f resources="$(RESOURCE_SCOPE)" \
		-f retention_days="$(RETENTION_DAYS)" \
		-f dry_run=false \
		-f include_archived="$(INCLUDE_ARCHIVED)" \
		-f excluded_repositories="$(EXCLUDED_REPOSITORIES)"
	@echo "Cleanup requested. Use 'make cleanup.watch' to follow it."

cleanup.watch cw: ## Watch the latest cleanup run
	@run_id="$$(gh run list --repo "$(REPO)" --workflow "$(WORKFLOW)" --limit 1 --json databaseId --jq '.[0].databaseId')"; \
	test -n "$$run_id" || { echo "No cleanup workflow run was found." >&2; exit 1; }; \
	gh run watch "$$run_id" --repo "$(REPO)" --exit-status

cleanup.logs cl: ## Show logs from the latest cleanup run
	@run_id="$$(gh run list --repo "$(REPO)" --workflow "$(WORKFLOW)" --limit 1 --json databaseId --jq '.[0].databaseId')"; \
	test -n "$$run_id" || { echo "No cleanup workflow run was found." >&2; exit 1; }; \
	gh run view "$$run_id" --repo "$(REPO)" --log

cleanup.run.list crl: ## Show runs from workflow
	@gh run list --repo "$(REPO)" --workflow "$(WORKFLOW)"

gh.repo.list grl: ## Show repo list
	@gh repo list

gh.repo.run.list grrl: ## Show repo run list
	@bash sh/repo-run-list.sh

gh.repo.run.list.failure grrlf: ## Show repo run list failure
	@STATUS=failure bash sh/repo-run-list.sh

gh.repo.list.branch.protected grlbp: ## Show repo list branch protected
	@bash sh/repo-list-branch-protected.sh

gh.repo.list.settings grls: ## Show repo list settings
	@bash sh/repo-list-settings.sh

gh.repo.apply.settings gras: ## Apply repo settings
	@bash sh/repo-apply-settings.sh
