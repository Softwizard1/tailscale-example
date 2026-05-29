# Tailnet Private Service Demo — task runner
# .PHONY ensures targets always run (they are commands, not files).
.DEFAULT_GOAL := help
.PHONY: help bootstrap deploy start stop restart doctor demo logs purge

help:        ## Show this help
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | sed 's/:.*##/ —/' | sort
bootstrap:   ## Preflight checks (deps, .env, compose)
	@bash scripts/bootstrap.sh
deploy:      ## One command: preflight → start → health check
	@bash scripts/deploy.sh
start:       ## Start the tailnet + private services
	@bash scripts/start.sh
stop:        ## Stop the stack (keep state)
	@bash scripts/stop.sh
restart:     ## Stop (purge state) and start fresh
	@bash scripts/stop.sh --purge && bash scripts/start.sh
doctor:      ## Diagnostics + the full validation suite
	@bash scripts/doctor.sh
demo:        ## Launch the live demo cockpit (http://127.0.0.1:8700)
	@bash scripts/demo.sh
logs:        ## Tail logs from all containers
	@$$(grep -q 'docker compose' scripts/lib.sh && echo docker compose || echo docker-compose) logs -f
purge:       ## Stop and wipe all Tailscale state volumes
	@bash scripts/stop.sh --purge
