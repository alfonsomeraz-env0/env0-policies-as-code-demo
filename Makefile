POLICIES := baseline production
OPA      ?= opa
TF       ?= terraform

.PHONY: help test fmt fmt-check check ci validate

help:
	@echo "make test       run the Rego unit tests for every policy folder"
	@echo "make check      type-check the policies"
	@echo "make fmt        format the policies and tests in place"
	@echo "make ci         fmt-check + check + test (what CI runs)"
	@echo "make validate   terraform fmt/validate for app/ and control-plane/"

# Each folder is a separate env0 policy, so it is tested on its own.
test:
	@for p in $(POLICIES); do \
		echo "== $$p"; \
		$(OPA) test policies/$$p tests/$$p -v || exit 1; \
	done

check:
	@for p in $(POLICIES); do $(OPA) check policies/$$p tests/$$p || exit 1; done

fmt:
	$(OPA) fmt -w policies tests

fmt-check:
	$(OPA) fmt --fail -l policies tests

ci: fmt-check check test

validate:
	$(TF) fmt -check -recursive app control-plane
	@for d in app control-plane; do \
		(cd $$d && $(TF) init -backend=false -input=false > /dev/null && $(TF) validate) || exit 1; \
	done
