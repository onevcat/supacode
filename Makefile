# Sensible defaults
.ONESHELL:
SHELL := bash
.SHELLFLAGS := -e -u -c -o pipefail
.DELETE_ON_ERROR:
MAKEFLAGS += --warn-undefined-variables
MAKEFLAGS += --no-builtin-rules

# Derived values (DO NOT TOUCH).
CURRENT_MAKEFILE_PATH := $(abspath $(lastword $(MAKEFILE_LIST)))
CURRENT_MAKEFILE_DIR := $(patsubst %/,%,$(dir $(CURRENT_MAKEFILE_PATH)))
GHOSTTY_XCFRAMEWORK_PATH := $(CURRENT_MAKEFILE_DIR)/Frameworks/GhosttyKit.xcframework

.DEFAULT_GOAL := help
.PHONY: serve build-ghostty-xcframework build-app run-app install-dev-build sync-ghostty-resources lint test update-wt bump-version

help:  # Display this help.
	@-+echo "Run make with one of the following targets:"
	@-+echo
	@-+grep -Eh "^[a-z-]+:.*#" $(CURRENT_MAKEFILE_PATH) | sed -E 's/^(.*:)(.*#+)(.*)/  \1 @@@ \3 /' | column -t -s "@@@"

build-ghostty-xcframework: $(GHOSTTY_XCFRAMEWORK_PATH) # Build ghostty framework

$(GHOSTTY_XCFRAMEWORK_PATH):
	git submodule update --init --recursive
	mise install
	@cd $(CURRENT_MAKEFILE_DIR)/ThirdParty/ghostty && mise exec -- zig build -Doptimize=ReleaseFast -Demit-xcframework=true -Dsentry=false
	rsync -a ThirdParty/ghostty/macos/GhosttyKit.xcframework Frameworks

sync-ghostty-resources: # Sync ghostty resources (themes, docs) over to the main repo
	@src="$(CURRENT_MAKEFILE_DIR)/ThirdParty/ghostty/zig-out/share/ghostty"; \
	dst="$(CURRENT_MAKEFILE_DIR)/supacode/Resources/ghostty"; \
	if [ ! -d "$$src" ]; then \
		echo "ghostty resources not found: $$src"; \
		echo "run: make build-ghostty-xcframework"; \
		exit 1; \
	fi; \
	mkdir -p "$$dst"; \
	rsync -a --delete "$$src/" "$$dst/"

build-app: build-ghostty-xcframework # Build the macOS app (Debug)
	bash -o pipefail -c 'xcodebuild -project supacode.xcodeproj -scheme supacode -configuration Debug build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | mise exec -- xcsift -qw'

run-app: build-app # Build then launch (Debug) with log streaming
	@settings="$$(xcodebuild -project supacode.xcodeproj -scheme supacode -configuration Debug -showBuildSettings -json 2>/dev/null)"; \
	build_dir="$$(echo "$$settings" | jq -r '.[0].buildSettings.BUILT_PRODUCTS_DIR')"; \
	product="$$(echo "$$settings" | jq -r '.[0].buildSettings.FULL_PRODUCT_NAME')"; \
	exec_name="$$(echo "$$settings" | jq -r '.[0].buildSettings.EXECUTABLE_NAME')"; \
	"$$build_dir/$$product/Contents/MacOS/$$exec_name"

install-dev-build: build-app # install dev build to /Applications
	@settings="$$(xcodebuild -project supacode.xcodeproj -scheme supacode -configuration Debug -showBuildSettings -json 2>/dev/null)"; \
	build_dir="$$(echo "$$settings" | jq -r '.[0].buildSettings.BUILT_PRODUCTS_DIR')"; \
	product="$$(echo "$$settings" | jq -r '.[0].buildSettings.FULL_PRODUCT_NAME')"; \
	src="$$build_dir/$$product"; \
	dst="/Applications/$$product"; \
	if [ ! -d "$$src" ]; then \
		echo "app not found: $$src"; \
		exit 1; \
	fi; \
	echo "copying $$src -> $$dst"; \
	rm -rf "$$dst"; \
	ditto "$$src" "$$dst"; \
	echo "installed $$dst"

lint: # Run swiftlint
	mise exec -- swiftlint --quiet

test: build-ghostty-xcframework
	bash -o pipefail -c 'xcodebuild test -project supacode.xcodeproj -scheme supacode -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | mise exec -- xcsift -qw'

format: # Swift format
	swift-format -p --in-place --recursive --configuration ./.swift-format.json supacode supacodeTests

update-wt: # Download git-wt binary to Resources
	@mkdir -p "$(CURRENT_MAKEFILE_DIR)/supacode/Resources/git-wt"
	@curl -fsSL "https://raw.githubusercontent.com/khoi/git-wt/refs/heads/main/wt" -o "$(CURRENT_MAKEFILE_DIR)/supacode/Resources/git-wt/wt"
	@chmod +x "$(CURRENT_MAKEFILE_DIR)/supacode/Resources/git-wt/wt"

bump-version: # Bump app version (usage: make bump-version VERSION=x.x.x [BUILD=123])
	@if [ -z "$(VERSION)" ]; then \
		echo "error: VERSION required (e.g., make bump-version VERSION=1.2.3 [BUILD=123])"; \
		exit 1; \
	fi; \
	if ! echo "$(VERSION)" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$$'; then \
		echo "error: VERSION must be in x.x.x format"; \
		exit 1; \
	fi; \
	if [ -z "$(BUILD)" ]; then \
		build="$$(/usr/bin/awk -F' = ' '/CURRENT_PROJECT_VERSION = [0-9]+;/{gsub(/;/,"",$$2);print $$2; exit}' "$(CURRENT_MAKEFILE_DIR)/supacode.xcodeproj/project.pbxproj")"; \
		if [ -z "$$build" ]; then \
			echo "error: CURRENT_PROJECT_VERSION not found"; \
			exit 1; \
		fi; \
		build="$$((build + 1))"; \
	else \
		if ! echo "$(BUILD)" | grep -qE '^[0-9]+$$'; then \
			echo "error: BUILD must be an integer"; \
			exit 1; \
		fi; \
		build="$(BUILD)"; \
	fi; \
	sed -i '' 's/MARKETING_VERSION = [0-9.]*;/MARKETING_VERSION = $(VERSION);/g' \
		"$(CURRENT_MAKEFILE_DIR)/supacode.xcodeproj/project.pbxproj"; \
	sed -i '' "s/CURRENT_PROJECT_VERSION = [0-9]*;/CURRENT_PROJECT_VERSION = $$build;/g" \
		"$(CURRENT_MAKEFILE_DIR)/supacode.xcodeproj/project.pbxproj"; \
	echo "version bumped to $(VERSION) (build $$build)"
