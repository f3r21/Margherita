APP_NAME := Margherita
BUNDLE   := $(APP_NAME).app
EXEC     := .build/release/$(APP_NAME)
SOURCES  := $(shell find Sources -name '*.swift')

.PHONY: build run install clean dmg install-hook uninstall-hook

build: $(BUNDLE)

$(BUNDLE): $(EXEC) Info.plist
	@rm -rf $(BUNDLE)
	@mkdir -p $(BUNDLE)/Contents/MacOS
	@mkdir -p $(BUNDLE)/Contents/Resources
	@cp $(EXEC) $(BUNDLE)/Contents/MacOS/
	@cp Info.plist $(BUNDLE)/Contents/
	@cp scripts/statusline-indicator.sh $(BUNDLE)/Contents/Resources/
	@chmod +x $(BUNDLE)/Contents/Resources/statusline-indicator.sh
	@if [ -f resources/AppIcon.icns ]; then cp resources/AppIcon.icns $(BUNDLE)/Contents/Resources/; fi
	@codesign --force --deep --sign - $(BUNDLE)
	@touch $(BUNDLE)
	@echo "Built and signed $(BUNDLE)"

$(EXEC): $(SOURCES) Package.swift
	swift build -c release

run: build
	@killall $(APP_NAME) 2>/dev/null || true
	open $(BUNDLE)

install: build
	@rm -rf /Applications/$(BUNDLE)
	cp -R $(BUNDLE) /Applications/
	@echo "Installed to /Applications/$(BUNDLE)"

dmg: build
	@echo "Creating DMG package..."
	@rm -rf dmg_staging Margherita.dmg
	@mkdir -p dmg_staging
	@cp -R $(BUNDLE) dmg_staging/
	@ln -s /Applications dmg_staging/Applications
	@hdiutil create -volname "Margherita" -srcfolder dmg_staging -ov -format UDZO Margherita.dmg
	@rm -rf dmg_staging
	@echo "Created Margherita.dmg successfully!"

clean:
	swift package clean
	rm -rf $(BUNDLE) .build Margherita.dmg dmg_staging

# Installs just the statusLine hook (bash + jq, no app/Xcode/Swift needed).
# For the console usage line without the menu bar icon at all.
install-hook:
	@./scripts/install-hook.sh

uninstall-hook:
	@./scripts/uninstall-hook.sh
