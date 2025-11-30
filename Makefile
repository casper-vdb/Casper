.PHONY: import-casper load-test-casper load-test-casper-save recall-casper recall-casper-save collect-casper-metrics

# Import vectors from binary file using Python script
import-casper:
	@if [ -z "$(IMPORT_PATH)" ]; then \
		echo "Error: IMPORT_PATH environment variable is required"; \
		echo "Usage: make import-casper-python IMPORT_PATH=path/to/vectors.bin"; \
		exit 1; \
	fi
	@echo "Importing vectors (Python) from: $(IMPORT_PATH)"
	@python3 scripts/import/import.py $(IMPORT_PATH) --base-url http://localhost:8080 --collection demo

# Load test with Apache Bench
load-test-casper:
	@ab -p json/casper/req.json -c 32 -n 300000 -k -T 'application/json' "http://localhost:8080/collection/demo/search?limit=10"

load-test-casper-save:
	@./scripts/ab.sh --base-url http://localhost:8080 --collection demo --body json/casper/req.json --out-dir metrics

recall-casper:
	@echo "Running recall evaluation ..."
	@python3 scripts/recall/recall.py --base data.bin --collection demo --k 10 --num-queries 1000 --metric ip

recall-casper-save:
	@./scripts/recall.sh --backend casper --base-url http://localhost:8080 --base data.bin --collection demo --num-queries 1000 --metric ip --out-dir metrics

# Combo: run both load-test-casper-save and recall-casper-save
collect-casper-metrics:
	@echo "Running load-test-casper-save and recall-casper-save ..."
	@$(MAKE) load-test-casper-save
	@$(MAKE) recall-casper-save
