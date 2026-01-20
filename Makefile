# Derived values (DO NOT TOUCH).
CURRENT_MAKEFILE_PATH := $(abspath $(lastword $(MAKEFILE_LIST)))
CURRENT_MAKEFILE_DIR := $(patsubst %/,%,$(dir $(CURRENT_MAKEFILE_PATH)))

.DEFAULT_GOAL := help
.PHONY: serve build-ghostty-xcframework build-app run-app sync-ghostty-resources

help:  # Display this help.
	@-+echo "Run make with one of the following targets:"
	@-+echo
	@-+grep -Eh "^[a-z-]+:.*#" $(CURRENT_MAKEFILE_PATH) | sed -E 's/^(.*:)(.*#+)(.*)/  \1 @@@ \3 /' | column -t -s "@@@"

build-ghostty-xcframework: # Build ghostty framework
	@cd $(CURRENT_MAKEFILE_DIR) && git submodule update --init --recursive
	@cd $(CURRENT_MAKEFILE_DIR) && mise install
	@cd $(CURRENT_MAKEFILE_DIR)/ThirdParty/ghostty && mise exec -- zig build -Doptimize=ReleaseFast -Demit-xcframework=true -Dsentry=false
	@cd $(CURRENT_MAKEFILE_DIR) && rsync -a ThirdParty/ghostty/macos/GhosttyKit.xcframework Frameworks

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

build-app: # Build the macOS app (Debug)
	@cd $(CURRENT_MAKEFILE_DIR) && xcodebuild -project supacode.xcodeproj -scheme supacode -configuration Debug build

run-app: build-app # Build then launch (Debug)
	@settings="$$(xcodebuild -project supacode.xcodeproj -scheme supacode -configuration Debug -showBuildSettings)"; \
	build_dir="$$(echo "$$settings" | sed -n 's/^ *BUILT_PRODUCTS_DIR = //p' | head -n 1)"; \
	product="$$(echo "$$settings" | sed -n 's/^ *FULL_PRODUCT_NAME = //p' | head -n 1)"; \
	open "$$build_dir/$$product"
