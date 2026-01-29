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
GHOSTTY_RESOURCE_PATH := $(CURRENT_MAKEFILE_DIR)/Resources/ghostty
GHOSTTY_TERMINFO_PATH := $(CURRENT_MAKEFILE_DIR)/Resources/terminfo
GHOSTTY_BUILD_OUTPUTS := $(GHOSTTY_XCFRAMEWORK_PATH) $(GHOSTTY_RESOURCE_PATH) $(GHOSTTY_TERMINFO_PATH)
VERSION ?=
BUILD ?=
FILES_FILE ?=

.DEFAULT_GOAL := help
.PHONY: serve build-ghostty-xcframework build-app run-app install-dev-build sync-ghostty-resources lint test update-wt bump-version bump-and-release install-git-hooks

help:  # Display this help.
	@-+echo "Run make with one of the following targets:"
	@-+echo
	@-+grep -Eh "^[a-z-]+:.*#" $(CURRENT_MAKEFILE_PATH) | sed -E 's/^(.*:)(.*#+)(.*)/  \1 @@@ \3 /' | column -t -s "@@@"

build-ghostty-xcframework: $(GHOSTTY_BUILD_OUTPUTS) # Build ghostty framework

$(GHOSTTY_BUILD_OUTPUTS):
	@cd $(CURRENT_MAKEFILE_DIR)/ThirdParty/ghostty && mise exec -- zig build -Doptimize=ReleaseFast -Demit-xcframework=true -Dsentry=false
	rsync -a ThirdParty/ghostty/macos/GhosttyKit.xcframework Frameworks
	@src="$(CURRENT_MAKEFILE_DIR)/ThirdParty/ghostty/zig-out/share/ghostty"; \
	dst="$(GHOSTTY_RESOURCE_PATH)"; \
	terminfo_src="$(CURRENT_MAKEFILE_DIR)/ThirdParty/ghostty/zig-out/share/terminfo"; \
	terminfo_dst="$(GHOSTTY_TERMINFO_PATH)"; \
	mkdir -p "$$dst"; \
	rsync -a --delete "$$src/" "$$dst/"; \
	mkdir -p "$$terminfo_dst"; \
	rsync -a --delete "$$terminfo_src/" "$$terminfo_dst/"

build-app: build-ghostty-xcframework # Build the macOS app (Debug)
	bash -o pipefail -c 'xcodebuild -project supacode.xcodeproj -scheme supacode -configuration Debug build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -skipMacroValidation 2>&1 | mise exec -- xcsift -qw --format toon'

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
	if [ -n "$(FILES_FILE)" ]; then \
		if [ ! -s "$(FILES_FILE)" ]; then \
			exit 0; \
		fi; \
		while IFS= read -r -d '' file; do \
			mise exec -- swiftlint --quiet --path "$$file"; \
		done < "$(FILES_FILE)"; \
	else \
		mise exec -- swiftlint --quiet; \
	fi

test: build-ghostty-xcframework
	xcodebuild test -project supacode.xcodeproj -scheme supacode -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -skipMacroValidation 2>&1

format: # Swift format
	if [ -n "$(FILES_FILE)" ]; then \
		if [ ! -s "$(FILES_FILE)" ]; then \
			exit 0; \
		fi; \
		xargs -0 swift-format -p --in-place --configuration ./.swift-format.json -- < "$(FILES_FILE)"; \
		while IFS= read -r -d '' file; do \
			mise exec -- swiftlint --fix --quiet --path "$$file"; \
		done < "$(FILES_FILE)"; \
	else \
		swift-format -p --in-place --recursive --configuration ./.swift-format.json supacode supacodeTests; \
		mise exec -- swiftlint --fix --quiet; \
	fi

install-git-hooks: # Install git hooks to format/lint staged files
	@mkdir -p "$(CURRENT_MAKEFILE_DIR)/.githooks"
	@git config core.hooksPath "$(CURRENT_MAKEFILE_DIR)/.githooks"
	@chmod +x "$(CURRENT_MAKEFILE_DIR)/.githooks/pre-commit"

update-wt: # Download git-wt binary to Resources
	@mkdir -p "$(CURRENT_MAKEFILE_DIR)/Resources/git-wt"
	@curl -fsSL "https://raw.githubusercontent.com/khoi/git-wt/refs/heads/main/wt" -o "$(CURRENT_MAKEFILE_DIR)/Resources/git-wt/wt"
	@chmod +x "$(CURRENT_MAKEFILE_DIR)/Resources/git-wt/wt"
	@git add "$(CURRENT_MAKEFILE_DIR)/Resources/git-wt/wt"
	@git commit -m "update git-wt"

bump-version: # Bump app version (usage: make bump-version [VERSION=x.x.x] [BUILD=123])
	@if [ -z "$(VERSION)" ]; then \
		current="$$(/usr/bin/awk -F' = ' '/MARKETING_VERSION = [0-9.]+;/{gsub(/;/,"",$$2);print $$2; exit}' "$(CURRENT_MAKEFILE_DIR)/supacode.xcodeproj/project.pbxproj")"; \
		if [ -z "$$current" ]; then \
			echo "error: MARKETING_VERSION not found"; \
			exit 1; \
		fi; \
		major="$$(echo "$$current" | cut -d. -f1)"; \
		minor="$$(echo "$$current" | cut -d. -f2)"; \
		patch="$$(echo "$$current" | cut -d. -f3)"; \
		version="$$major.$$minor.$$((patch + 1))"; \
	else \
		if ! echo "$(VERSION)" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$$'; then \
			echo "error: VERSION must be in x.x.x format"; \
			exit 1; \
		fi; \
		version="$(VERSION)"; \
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
	sed -i '' "s/MARKETING_VERSION = [0-9.]*;/MARKETING_VERSION = $$version;/g" \
		"$(CURRENT_MAKEFILE_DIR)/supacode.xcodeproj/project.pbxproj"; \
	sed -i '' "s/CURRENT_PROJECT_VERSION = [0-9]*;/CURRENT_PROJECT_VERSION = $$build;/g" \
		"$(CURRENT_MAKEFILE_DIR)/supacode.xcodeproj/project.pbxproj"; \
	git add "$(CURRENT_MAKEFILE_DIR)/supacode.xcodeproj/project.pbxproj"; \
	git commit -m "bump v$$version"; \
	git tag -a "v$$version" -m "v$$version"; \
	echo "version bumped to $$version (build $$build), tagged v$$version"

bump-and-release: bump-version # Bump version and push tags to trigger release
	git push --follow-tags
