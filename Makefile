# ── dvirtd Makefile — install / uninstall / check ─────────────────────────
# Orchestration: bin/dvirtd.sh  |  Build/version mgmt: bin/dvirtmg.sh

DVIRTD := /opt/dvirtd
WRAPPER_DIR := /usr/local/bin
COMPLETION_DIR := /usr/share/bash-completion/completions
.PHONY: help check install uninstall

help:           ### Show this help
	@awk 'BEGIN {FS = ":.*###"; printf "make \033[36m<command>\033[0m\n\nUsage:\033[36m\033[0m\n"} /^[a-zA-Z_-]+:.*?###/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo
	@echo '  Commands installed to $(WRAPPER_DIR):'
	@echo '    dvirtd [run|list|help]   Container launcher'
	@echo '    dvirtmg [build|list|outdated|current|purge]  Version manager'
	@echo
	@echo '  Use $(DVIRTD) for development entry point:'
	@echo '    $(DVIRTD)/bin/dvirtd.sh ...'

check:          ### Shell syntax check of all scripts
	@bash -n bin/dvirtmg.sh
	@bash -n bin/dvirtd.sh
	@bash -n lib/orchestrator.sh
	@bash -n lib/display.sh
	@bash -n lib/env.sh
	@bash -n lib/includes/logging.sh
	@bash -n lib/includes/versions.sh
	@bash -n lib/completions/dvirtd
	@bash -n lib/completions/dvirtmg
	@echo 'All scripts pass syntax check'

install:        ### Copy project to $(DVIRTD) and create wrappers in $(WRAPPER_DIR)
	@if [ -d $(DVIRTD) ]; then \
	    if [ ! -f $(DVIRTD)/Makefile ]; then \
	        echo "Error: $(DVIRTD) exists but is not this project — aborting."; \
	        exit 1; \
	    fi; \
	    src_hash=$$(cksum Makefile | awk '{print $$1}'); \
	    dst_hash=$$(sudo cksum $(DVIRTD)/Makefile | awk '{print $$1}'); \
	    if [ "$$src_hash" != "$$dst_hash" ]; then \
	        echo "Error: $(DVIRTD) contains a different version of this project — aborting."; \
	        exit 1; \
	    fi; \
	    echo "Same project detected at $(DVIRTD) — overwriting."; \
	fi
	sudo install -d $(DVIRTD)
	tar --exclude='.git' --exclude='.cache' --exclude='.wssdata' \
	    --exclude='.tmp' --exclude='.env' -c . \
	  | sudo tar -C $(DVIRTD) -x
	@printf '#!/usr/bin/env bash\nexec $(DVIRTD)/bin/dvirtd.sh "$$@"\n' | sudo tee $(WRAPPER_DIR)/dvirtd > /dev/null
	@sudo chmod +x $(WRAPPER_DIR)/dvirtd
	@printf '#!/usr/bin/env bash\nexec $(DVIRTD)/bin/dvirtmg.sh "$$@"\n' | sudo tee $(WRAPPER_DIR)/dvirtmg > /dev/null
	@sudo chmod +x $(WRAPPER_DIR)/dvirtmg
	@sudo install -D -m 644 lib/completions/dvirtd $(COMPLETION_DIR)/dvirtd
	@sudo install -D -m 644 lib/completions/dvirtmg $(COMPLETION_DIR)/dvirtmg
	@echo "Installed: $(DVIRTD) + wrappers + completions"

uninstall:      ### Remove $(DVIRTD), wrappers, and completions
	sudo rm -rf $(DVIRTD)
	sudo rm -f $(WRAPPER_DIR)/dvirtd $(WRAPPER_DIR)/dvirtmg
	@sudo rm -f $(COMPLETION_DIR)/dvirtd $(COMPLETION_DIR)/dvirtmg
	@echo "Removed: $(DVIRTD), wrappers, and completions"
