.PHONY: import load-test load-test-save recall recall-save collect-metrics

# Default base URL for Casper HTTP API (can be overridden: make ... BASE_URL=http://host:port)
BASE_URL ?= http://localhost:8080

# Default path to benchmark data (can be overridden: make ... IMPORT_PATH=path/to/data.bin)
IMPORT_PATH ?= casper-bench-data/data/data.bin

# Default path to Apache Bench request body
AB_REQ_PATH ?= casper-bench-data/json/casper/req.json

# Import vectors from binary file using Python script
import:
	@echo "Importing vectors to Casper Vector Database"
	@python3 scripts/import/import.py $(IMPORT_PATH) --base-url $(BASE_URL) --collection demo

# Load test with Apache Bench
load-test:
	@ab -p $(AB_REQ_PATH) -c 32 -n 300000 -k -T 'application/json' "$(BASE_URL)/collection/demo/search?limit=10&output=bin"

load-test-save:
	@./scripts/ab.sh --base-url $(BASE_URL) --collection demo --body $(AB_REQ_PATH) --out-dir metrics

recall:
	@echo "Running recall evaluation ..."
	@python3 scripts/recall/recall.py --base $(IMPORT_PATH) --collection demo --k 10 --num-queries 1000 --metric ip --base-url $(BASE_URL)

recall-save:
	@./scripts/recall.sh --backend casper --base-url $(BASE_URL) --base $(IMPORT_PATH) --collection demo --num-queries 1000 --metric ip --out-dir metrics

# Combo: run both load-test-save and recall-save
collect-metrics:
	@echo "Running load-test-save and recall-save ..."
	@$(MAKE) load-test-save
	@$(MAKE) recall-save
