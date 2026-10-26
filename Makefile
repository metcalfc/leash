.DEFAULT_GOAL := help
export LEASH_UID := $(shell id -u)
export LEASH_GID := $(shell id -g)
export LEASH_SESSION ?= demo
.PHONY: help init up demo report logs down test test-docker lint clean spike-gw spike-up spike-report spike-record spike-preflight spike-verify

help:
	@echo 'make test     run the unit tests (no docker, no keys)'
	@echo 'make test-docker  check isolated bridge host access and gateway reachability (Docker 28+)'
	@echo ''
	@echo 'spike (a QEMU VM whose only way out is leash; see spike/HANDOFF.md):'
	@echo 'make spike-gw       run the gateway for the spike (key from the keychain)'
	@echo 'make spike-up       mint capabilities, boot the locked VM'
	@echo 'make spike-report   spend and denials for the spike session'
	@echo 'make spike-preflight check live gateway, enabled route and fresh session budget'
	@echo 'make spike-verify   compare locked probes with provisioning positive controls'
	@echo 'make spike-record   record the demo with VHS'
	@echo ''
	@echo 'docker version:'
	@echo 'make init     mint session capabilities, write run/<session>.env'
	@echo 'make up       build and start gateway + agent containers'
	@echo 'make demo     walk through what the agent can and cannot do'
	@echo 'make report   spend and denials per session'
	@echo 'make down     stop everything; capabilities go inert'

init:
	./leash -c policy.json init

up: init
	mkdir -p workspace
	docker compose up -d --build

demo:
	./demo.sh

report:
	docker compose exec -T leash ./leash -c policy.json report

logs:
	docker compose logs -f leash

down:
	docker compose down

test:
	python3 -m unittest discover -s tests -v

test-docker:
	python3 tests/docker_network.py

lint:
	ruff check --select E,F,W,I,B,UP --line-length 120 leash tests/ spike/control-server.py
	shellcheck demo.sh spike/vm.sh spike/guest/*.sh spike/lima/*.sh

spike-gw:
	ANTHROPIC_API_KEY=$$(security find-generic-password -s leash-anthropic -w) \
	  ./leash -c spike/policy.json --session "$(LEASH_SESSION)" serve

spike-up:
	./leash -c spike/policy.json --session "$(LEASH_SESSION)" init
	./spike/vm.sh up

spike-report:
	./leash -c spike/policy.json --session "$(LEASH_SESSION)" report

spike-preflight:
	./leash -c spike/policy.json --session "$(LEASH_SESSION)" preflight --require-route anthropic --fresh

spike-verify:
	./spike/vm.sh verify

spike-record:
	vhs spike/record/demo.tape

clean: down
	rm -rf run workspace
