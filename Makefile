GOCMD=go
ENTRY_POINT_DIR=cmd
TARGETS=$(notdir $(wildcard $(ENTRY_POINT_DIR)/*))

GREEN  := $(shell tput -Txterm setaf 2)
YELLOW := $(shell tput -Txterm setaf 3)
WHITE  := $(shell tput -Txterm setaf 7)
CYAN   := $(shell tput -Txterm setaf 6)
RESET  := $(shell tput -Txterm sgr0)

.PHONY: all
all: help

## Build:
.PHONY: build
build: make_outdir $(TARGETS) ## Build your project and put the output binary in out/bin/

.PHONY: make_outdir
make_outdir:
	mkdir -p out/bin

.PHONY: $(TARGETS)
$(TARGETS):
	$(GOCMD) build -o out/bin/$@ ./$(ENTRY_POINT_DIR)/$@/

.PHONY: clean
clean: ## Remove build related file
	rm -fr ./out/bin

.PHONY: help
help: ## Show this help.
	@echo ''
	@echo 'Usage:'
	@echo '  ${YELLOW}make${RESET} ${GREEN}<target>${RESET}'
	@echo ''
	@echo 'Targets:'
	@awk 'BEGIN {FS = ":.*?## "} { \
		if (/^[a-zA-Z_-]+:.*?##.*$$/) { \
			printf "    ${YELLOW}%-30s${GREEN}%s${RESET}\n", $$1, $$2 \
		} \
		else if (/^## .*$$/) {printf "  ${CYAN}%s${RESET}\n", substr($$1,4)} \
		}' $(MAKEFILE_LIST)

