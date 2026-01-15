.PHONY: import load-test load-test-save recall recall-save
.PHONY: metrics metrics-qdrant metrics-quick

# Default path to benchmark data (can be overridden: make ... IMPORT_PATH=path/to/data.bin)
IMPORT_PATH ?= casper-bench-data/data/data.bin

# Apache Bench request body JSON.
# Default is the example request body from casper-bench-data.
AB_BODY ?= casper-bench-data/json/casper/req.json

# Default base URL for Casper HTTP API (can be overridden: make ... BASE_URL=http://host:port)
BASE_URL ?= http://localhost:8080

# Default collection name to use in Makefile targets (override: make -f Makefile ... COLLECTION=my_collection)
COLLECTION ?= test_collection

# Casper python-client connection settings (used by metrics: PQ upload/delete via python-client)
CASPER_HOST ?= http://127.0.0.1
CASPER_HTTP_PORT ?= 8080
CASPER_GRPC_PORT ?= 50051

# Casper end-to-end metrics settings (used by `make metrics`)
CASPER_METRICS_VERSION ?= v0.0.0
CASPER_METRICS_COLLECTION ?= test_collection
CASPER_METRICS_BASE ?= $(IMPORT_PATH)
CASPER_METRICS_PQ_NAME ?= pq_test

# Qdrant settings (used by `make metrics-qdrant`)
QDRANT_URL ?= http://localhost:6333
QDRANT_VERSION ?= 1.16.0
QDRANT_COLLECTION_PREFIX ?= test_collection
QDRANT_BASE ?= $(IMPORT_PATH)

# Import vectors from binary file using Python script
import:
	@echo "Importing vectors to Casper Vector Database"
	@python3 scripts/import/import.py $(IMPORT_PATH) --base-url $(BASE_URL) --collection $(COLLECTION)

# Load test with Apache Bench
load-test:
	@if [ -z "$(AB_BODY)" ]; then echo "Error: AB_BODY is required (path to request JSON). Example: make -f Makefile $@ AB_BODY=casper-bench-data/json/casper/req.json"; exit 1; fi
	@ab -p $(AB_BODY) -c 32 -n 300000 -k -T 'application/json' "$(BASE_URL)/collection/$(COLLECTION)/search?limit=10&output=bin"

load-test-save:
	@if [ -z "$(AB_BODY)" ]; then echo "Error: AB_BODY is required (path to request JSON). Example: make -f Makefile $@ AB_BODY=casper-bench-data/json/casper/req.json"; exit 1; fi
	@./scripts/ab/casper/ab.sh --base-url $(BASE_URL) --collection $(COLLECTION) --body $(AB_BODY) --out-dir metrics

recall:
	@echo "Running recall evaluation ..."
	@python3 scripts/recall/recall.py --base $(IMPORT_PATH) --collection $(COLLECTION) --k 10 --num-queries 1000 --metric ip --base-url $(BASE_URL)

recall-save:
	@./scripts/recall.sh --backend casper --base-url $(BASE_URL) --base $(IMPORT_PATH) --collection $(COLLECTION) --num-queries 1000 --metric ip --out-dir metrics

# Combo: run both load-test-save and recall-save
metrics-quick:
	@echo "Running load-test-save and recall-save ..."
	@$(MAKE) load-test-save
	@$(MAKE) recall-save

# Casper end-to-end metrics (create -> import -> PQ -> index(f32/i8/pq) -> ab+recall -> cleanup)
metrics:
	@echo "Running Casper metrics scenario ..."
	@./scripts/metrics/casper/metrics.sh \
		--base-url "$(BASE_URL)" \
		--casper-version "$(CASPER_METRICS_VERSION)" \
		--collection "$(CASPER_METRICS_COLLECTION)" \
		--base "$(CASPER_METRICS_BASE)" \
		--pq-name "$(CASPER_METRICS_PQ_NAME)" \
		--casper-host "$(CASPER_HOST)" \
		--casper-http-port "$(CASPER_HTTP_PORT)" \
		--casper-grpc-port "$(CASPER_GRPC_PORT)" \
		--ab-body "$(AB_BODY)" \
		--metric ip \
		--num-queries 1000

# Qdrant end-to-end metrics (create -> import -> load-test -> recall -> delete)
metrics-qdrant:
	@echo "Running Qdrant metrics (version=$(QDRANT_VERSION)) ..."
	@./scripts/metrics/qdrant/metrics.sh \
		--qdrant-url "$(QDRANT_URL)" \
		--qdrant-version "$(QDRANT_VERSION)" \
		--collection-prefix "$(QDRANT_COLLECTION_PREFIX)" \
		--base "$(QDRANT_BASE)" \
		--ab-body "$(AB_BODY)" \
		--metric ip \
		--num-queries 1000
