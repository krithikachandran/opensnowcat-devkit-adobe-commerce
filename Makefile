.PHONY: help init-env run-kafka run-warpstream stop logs clean kafka-ui warpstream-console pull-schemas upload-schemas iglu-health status snowflake-keypair fetch-enrichment-data

# Default target
help:
	@echo "OpenSnowcat Devkit - Available commands:"
	@echo ""
	@echo "  make init-env           - Create .env from .env.example with random local secrets"
	@echo "  make run-kafka          - Start environment with Apache Kafka"
	@echo "  make run-warpstream     - Start environment with Warpstream"
	@echo "  make stop               - Stop all containers"
	@echo "  make logs               - Show logs from all containers"
	@echo "  make logs-follow        - Follow logs from all containers"
	@echo "  make clean              - Stop and remove all containers and volumes"
	@echo "  make kafka-ui           - Open Kafka UI in browser"
	@echo "  make warpstream-console - Get Warpstream console URL"
	@echo "  make iglu-health        - Check if Iglu Server is running"
	@echo "  make pull-schemas       - Pull schemas from Snowplow BDP to schemas/"
	@echo "  make upload-schemas     - Upload schemas from schemas/ to local Iglu Server"
	@echo "  make status             - Show topic message counts (quick health check)"
	@echo "  make snowflake-keypair  - Generate RSA key pair for Snowflake Snowpipe Streaming auth"
	@echo "  make fetch-enrichment-data - Download GeoLite2-City.mmdb + uap-core regexes"
	@echo ""

snowflake-keypair:
	@./scripts/generate-snowflake-keypair.sh

# Create .env from .env.example with auto-generated values for the local-only
# Iglu secrets. Cloud credentials (Snowflake, MaxMind, AWS, Snowplow Console)
# stay blank and must be filled in by hand.
init-env:
	@if [ -f .env ]; then \
		echo "ERROR: .env already exists. Delete it first if you want to regenerate."; \
		exit 1; \
	fi
	@cp .env.example .env
	@IGLU_KEY=$$(uuidgen | tr 'A-Z' 'a-z'); \
	IGLU_PASS=$$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32); \
	if [ "$$(uname)" = "Darwin" ]; then \
		sed -i '' "s|^IGLU_SUPER_API_KEY=.*|IGLU_SUPER_API_KEY=$$IGLU_KEY|" .env; \
		sed -i '' "s|^IGLU_DB_PASSWORD=.*|IGLU_DB_PASSWORD=$$IGLU_PASS|" .env; \
	else \
		sed -i "s|^IGLU_SUPER_API_KEY=.*|IGLU_SUPER_API_KEY=$$IGLU_KEY|" .env; \
		sed -i "s|^IGLU_DB_PASSWORD=.*|IGLU_DB_PASSWORD=$$IGLU_PASS|" .env; \
	fi
	@echo "✅ .env created with generated local secrets."
	@echo "   Next: open .env and fill in the cloud credentials"
	@echo "   (Snowflake, MaxMind, AWS, Snowplow Console)."

# Download data files required by the IP-lookup and ua-parser enrichments.
# - GeoLite2-City: free with a MaxMind account; set MAXMIND_LICENSE_KEY in .env
# - uap-core regexes.yaml: free, no auth
# IAB data is licensed/paid and must be placed manually under opensnowcat/enrichments-data/iab/
fetch-enrichment-data:
	@set -e; \
	. ./.env 2>/dev/null || true; \
	DATA_DIR=opensnowcat/enrichments-data; \
	mkdir -p $$DATA_DIR/maxmind $$DATA_DIR/uap $$DATA_DIR/iab; \
	echo "Fetching uap-core regexes.yaml..."; \
	curl -fsSL -o $$DATA_DIR/uap/regexes.yaml \
		https://raw.githubusercontent.com/ua-parser/uap-core/master/regexes.yaml; \
	echo "  → $$DATA_DIR/uap/regexes.yaml"; \
	if [ -z "$$MAXMIND_LICENSE_KEY" ]; then \
		echo ""; \
		echo "⚠️  MAXMIND_LICENSE_KEY not set in .env — skipping GeoLite2 download."; \
		echo "    Sign up free at https://www.maxmind.com/en/geolite2/signup,"; \
		echo "    then add MAXMIND_LICENSE_KEY=... to .env and re-run."; \
	else \
		echo "Fetching GeoLite2-City..."; \
		TMP=$$(mktemp -d); \
		curl -fsSL -o $$TMP/geolite.tar.gz \
			"https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-City&license_key=$$MAXMIND_LICENSE_KEY&suffix=tar.gz"; \
		tar -xzf $$TMP/geolite.tar.gz -C $$TMP; \
		find $$TMP -name 'GeoLite2-City.mmdb' -exec mv {} $$DATA_DIR/maxmind/GeoLite2-City.mmdb \;; \
		rm -rf $$TMP; \
		echo "  → $$DATA_DIR/maxmind/GeoLite2-City.mmdb"; \
		echo ""; \
		echo "✅ Data fetched. To enable IP lookup, set enabled: true in"; \
		echo "   opensnowcat/enrichments/ip_lookups_enrichment_config.json and restart the enricher."; \
	fi
	@echo ""
	@echo "ℹ️  IAB list is licensed and must be obtained separately from IAB Tech Lab."
	@echo "   Drop ip_exclude_current_cidr.txt, exclude_current.txt, include_current.txt"
	@echo "   into opensnowcat/enrichments-data/iab/ and flip the iab enrichment to enabled."

# Start with Apache Kafka
run-kafka:
	@echo "Starting OpenSnowcat with Apache Kafka..."
	@echo "Add '127.0.0.1  warp' to your /etc/hosts if not already done"
	docker compose up -d
	@echo ""
	@echo "✅ Environment started!"
	@echo "📊 Kafka UI: http://localhost:8081 (wait for KafkaUI to initialize)"
	@echo "📡 Collector: http://localhost:8080"
	@open http://localhost:8081 2>/dev/null || xdg-open http://localhost:8081 2>/dev/null || true

# Start with Warpstream
run-warpstream:
	@echo "Starting OpenSnowcat with Warpstream..."
	@echo "Add '127.0.0.1  warp' to your /etc/hosts if not already done"
	docker compose -f docker-compose.yml -f docker-compose.warpstream.yml up -d
	@echo ""
	@echo "⏳ Waiting for Warpstream to start..."
	@sleep 10
	@echo ""
	@echo "✅ Environment started!"
	@echo "📊 Kafka UI: http://localhost:8081 (wait for KafkaUI to initialize)"
	@echo "📡 Collector: http://localhost:8080"
	@echo ""
	@echo "🌐 Opening Warpstream Console and Kafka UI..."
	@CONSOLE_URL=$$(docker logs warp 2>&1 | grep "console.warpstream.com" | grep -o 'https:/[^[:space:]]*' | sed 's|https:/console|https://console|' | head -1); \
	if [ -n "$$CONSOLE_URL" ]; then \
		echo "Warpstream Console: $$CONSOLE_URL"; \
		open "$$CONSOLE_URL" 2>/dev/null || xdg-open "$$CONSOLE_URL" 2>/dev/null || echo "$$CONSOLE_URL"; \
	else \
		echo "Console URL not found yet, run: make warpstream-console"; \
	fi
	@sleep 2
	@open http://localhost:8081 2>/dev/null || xdg-open http://localhost:8081 2>/dev/null || true

# Stop all containers (works for both Kafka and Warpstream stacks — same project name)
stop:
	@echo "Stopping all containers..."
	@docker compose down 2>/dev/null || true
	@echo "✅ All containers stopped"

# Show logs
logs:
	@docker compose logs

# Follow logs
logs-follow:
	@docker compose logs -f

# Clean everything (stops containers and removes volumes — including Iglu schema DB)
clean:
	@echo "Stopping and removing all containers and volumes..."
	@docker compose down -v 2>/dev/null || true
	@echo "✅ Environment cleaned"

# Open Kafka UI
kafka-ui:
	@open http://localhost:8081 2>/dev/null || xdg-open http://localhost:8081 2>/dev/null || echo "Open http://localhost:8081 in your browser"

# Get Warpstream console URL
warpstream-console:
	@echo "🌐 Warpstream Console URL:"
	@docker logs warp 2>&1 | grep "console.warpstream.com" | grep -o 'https:/[^[:space:]]*' | sed 's|https:/console|https://console|' | head -1

# Check Iglu Server health
iglu-health:
	@echo "Checking Iglu Server..."
	@curl -s http://localhost:8181/api/meta/health | head -c 200 || echo "Iglu Server is not reachable at localhost:8181"

# Pull schemas from Snowplow BDP
pull-schemas:
	@echo "Pulling schemas from Snowplow BDP..."
	./scripts/pull-schemas.sh

# Upload schemas from schemas/ directory to local Iglu Server (sorted by version)
upload-schemas:
	@echo "Uploading schemas to local Iglu Server..."
	@. ./.env 2>/dev/null || true; \
	if [ -z "$$IGLU_SUPER_API_KEY" ]; then \
		echo "ERROR: IGLU_SUPER_API_KEY not set. Copy .env.example to .env first."; \
		exit 1; \
	fi; \
	IGLU_KEY=$$IGLU_SUPER_API_KEY; \
	if [ ! -d "schemas" ]; then \
		echo "No schemas/ directory found. Run 'make pull-schemas' first."; \
		exit 1; \
	fi; \
	OK=0; FAIL=0; \
	for schema_file in $$(find schemas -type f ! -name "*.md" ! -name ".*" | sort -t/ -k5 -V); do \
		REL=$${schema_file#schemas/}; \
		VENDOR=$$(echo "$$REL" | cut -d/ -f1); \
		NAME=$$(echo "$$REL" | cut -d/ -f2); \
		FORMAT=$$(echo "$$REL" | cut -d/ -f3); \
		VERSION=$$(echo "$$REL" | cut -d/ -f4); \
		RESULT=$$(curl -s -X PUT "http://localhost:8181/api/schemas/$${VENDOR}/$${NAME}/$${FORMAT}/$${VERSION}" \
			-H "apikey: $$IGLU_KEY" \
			-H "Content-Type: application/json" \
			-d @"$$schema_file" 2>&1); \
		if echo "$$RESULT" | grep -qi "already exists\|200\|201"; then \
			OK=$$((OK + 1)); \
		elif echo "$$RESULT" | grep -qi "error\|40[0-9]\|missing"; then \
			echo "  FAIL $$VENDOR/$$NAME/$$FORMAT/$$VERSION: $$RESULT"; \
			FAIL=$$((FAIL + 1)); \
		else \
			OK=$$((OK + 1)); \
		fi; \
	done; \
	echo "Uploaded $$OK schemas ($$FAIL failures)"

# Quick health check: show topic message counts
status:
	@echo "Topic message counts:"
	@docker exec warp /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --describe 2>/dev/null | \
		grep -E "^Topic:" | awk '{print $$1, $$2}' || echo "Kafka is not running"
	@echo ""
	@echo "Consumer group lag:"
	@docker exec warp /opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --all-groups --describe 2>/dev/null | \
		head -20 || echo "No consumer groups found"
