.PHONY: build run app install clean test dmg zip

# Build the executable (debug)
build:
	swift build

# Run in development mode (unbundled)
run:
	swift run

# Run tests
test:
	swift test

# Build the .app bundle (release)
app:
	@chmod +x scripts/build-app.sh
	@scripts/build-app.sh

# Build with custom version
# Usage: make app VERSION=1.2.0 BUILD_NUMBER=42
app-versioned:
	@chmod +x scripts/build-app.sh
	@VERSION=$(VERSION) BUILD_NUMBER=$(BUILD_NUMBER) scripts/build-app.sh

# Install to /Applications
install: app
	@echo "==> Installing to /Applications..."
	@rm -rf /Applications/AICP.app
	@cp -R dist/AICP.app /Applications/
	@echo "    Installed! Launch from /Applications or Spotlight."

# Uninstall from /Applications
uninstall:
	@echo "==> Removing AICP from /Applications..."
	@rm -rf /Applications/AICP.app
	@echo "    Done."

# Create DMG for distribution
dmg:
	@chmod +x scripts/build-app.sh
	@CREATE_DMG=1 scripts/build-app.sh

# Create ZIP for distribution
zip:
	@chmod +x scripts/build-app.sh
	@CREATE_ZIP=1 scripts/build-app.sh

# Clean build artifacts
clean:
	swift package clean
	rm -rf dist/
