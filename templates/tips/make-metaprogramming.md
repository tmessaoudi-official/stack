# Makefile Metaprogramming with `define` and `$(eval)`

**What it solves**: Makefiles with 50+ copy-pasted targets that differ only by a service name, environment, or flag. When you have targets like `start-web`, `start-api`, `start-worker` that are structurally identical, maintaining them individually means every change must be applied N times — and the Nth copy always has the typo.

## The macro pattern

Define a multi-line macro with `define`/`endef`, then expand it with `$(eval $(call ...))`:

```makefile
define make-service-targets
# $1 = service name
start-$(1):
	docker compose up -d $(1)

stop-$(1):
	docker compose stop $(1)

logs-$(1):
	docker compose logs -f $(1)

.PHONY: start-$(1) stop-$(1) logs-$(1)
endef

SERVICES := web api worker scheduler

$(foreach s,$(SERVICES),$(eval $(call make-service-targets,$(s))))
```

This generates `start-web`, `stop-web`, `logs-web`, `start-api`, `stop-api`, `logs-api`, etc. — all from one definition.

## `$(call macro,arg1,arg2)` syntax

Inside a macro body, positional arguments are `$(1)`, `$(2)`, `$(3)`:

```makefile
define deploy-target
deploy-$(1)-$(2):
	./deploy.sh --env=$(1) --region=$(2)

.PHONY: deploy-$(1)-$(2)
endef

$(eval $(call deploy-target,production,eu-west-1))
$(eval $(call deploy-target,staging,us-east-1))
```

## Variable expansion timing: `$$` vs `$`

This is the most common source of bugs in Makefile macros. Make expands `$` during macro definition/evaluation; the shell sees the result. Use `$$` when you want the shell to see a literal `$`:

```makefile
define shell-example
print-$(1):
	# $@ is a Make variable (target name) — expanded by Make:
	@echo "Building target: $@"
	# $$HOME is a shell variable — $$ becomes $ in the shell:
	@echo "Running as: $$USER"
	# $(1) is a macro argument — expanded by Make at eval time:
	@echo "Service: $(1)"
endef
```

Rule of thumb:
- `$(VAR)` — Make variable or macro argument, expanded at eval time
- `$$VAR` or `$${VAR}` — shell variable, passed through to the shell as `$VAR`
- `$@`, `$<`, `$^` — Make automatic variables (target, first dep, all deps) — these are Make variables, not shell

## `.PHONY` for generated targets

Generated targets still need `.PHONY` declarations if they don't produce a file. The `$(foreach)` + `$(eval)` pattern inside the macro handles this automatically (see the example above). You can also declare them in a separate loop:

```makefile
SERVICES := web api worker

.PHONY: $(foreach s,$(SERVICES),start-$(s) stop-$(s) logs-$(s))
```

## Gotcha: variable values must be resolved before `$(eval)`

Make expands variables lazily by default (`:=` for immediate, `=` for deferred). Inside a `$(foreach)` loop, use `:=` or be explicit:

```makefile
# Broken: $(SERVICE) may not be set when the foreach runs
$(foreach SERVICE,$(SERVICES),$(eval $(call make-service-targets,$(SERVICE))))

# Correct: pass the value directly as a macro argument
$(foreach s,$(SERVICES),$(eval $(call make-service-targets,$(s))))
```

The variable `s` inside `$(foreach s,$(SERVICES),...)` is expanded immediately by the `foreach` function — no timing issue. Problems arise when you use a variable whose value is set later in the Makefile (deferred assignment `=`).

## Recursive `foreach` for two-dimensional targets

```makefile
ENVS    := staging production
REGIONS := eu-west-1 us-east-1

$(foreach e,$(ENVS),\
  $(foreach r,$(REGIONS),\
    $(eval $(call deploy-target,$(e),$(r)))))
```

Generates: `deploy-staging-eu-west-1`, `deploy-staging-us-east-1`, `deploy-production-eu-west-1`, `deploy-production-us-east-1`.
