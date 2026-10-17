.DEFAULT_GOAL := help
export LEASH_UID := $(shell id -u)
export LEASH_GID := $(shell id -g)
.PHONY: help init up demo report logs down test lint clean

help:
	@echo 'make test     run the unit tests (no docker, no keys)'
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

lint:
	ruff check --select E,F,W,I,B,UP --line-length 120 leash tests/

clean: down
	rm -rf run workspace
