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
.PHONY: serve build-ghostty-xcframework build-app run-app sync-ghostty-resources lint test update-wt

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
	xcodebuild -project supacode.xcodeproj -scheme supacode -configuration Debug build 2>&1 | xcsift -qw

run-app: build-app # Build then launch (Debug)
	@settings="$$(xcodebuild -project supacode.xcodeproj -scheme supacode -configuration Debug -showBuildSettings -json 2>/dev/null)"; \
	build_dir="$$(echo "$$settings" | jq -r '.[0].buildSettings.BUILT_PRODUCTS_DIR')"; \
	product="$$(echo "$$settings" | jq -r '.[0].buildSettings.FULL_PRODUCT_NAME')"; \
	open -n "$$build_dir/$$product"

lint: # Run swiftlint
	mise exec -- swiftlint --quiet

test: build-ghostty-xcframework
	xcodebuild test -project supacode.xcodeproj -scheme supacode -destination "platform=macOS" 2>&1 | xcsift -qw

format: # Swift format
	swift-format -p --in-place --recursive --configuration ./.swift-format.json supacode supacodeTests

update-wt: # Download git-wt binary to Resources
	@mkdir -p "$(CURRENT_MAKEFILE_DIR)/supacode/Resources/git-wt"
	@curl -fsSL "https://raw.githubusercontent.com/khoi/git-wt/refs/heads/main/wt" -o "$(CURRENT_MAKEFILE_DIR)/supacode/Resources/git-wt/wt"
	@chmod +x "$(CURRENT_MAKEFILE_DIR)/supacode/Resources/git-wt/wt"
