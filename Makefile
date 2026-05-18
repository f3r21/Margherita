APP_NAME := ClaudeIndicator
BUNDLE   := $(APP_NAME).app
EXEC     := .build/release/$(APP_NAME)
SOURCES  := $(shell find Sources -name '*.swift')

.PHONY: build run install clean

build: $(BUNDLE)

$(BUNDLE): $(EXEC) Info.plist
	@rm -rf $(BUNDLE)
	@mkdir -p $(BUNDLE)/Contents/MacOS
	@cp $(EXEC) $(BUNDLE)/Contents/MacOS/
	@cp Info.plist $(BUNDLE)/Contents/
	@touch $(BUNDLE)
	@echo "Built $(BUNDLE)"

$(EXEC): $(SOURCES) Package.swift
	swift build -c release

run: build
	@killall $(APP_NAME) 2>/dev/null || true
	open $(BUNDLE)

install: build
	@rm -rf /Applications/$(BUNDLE)
	cp -R $(BUNDLE) /Applications/
	@echo "Installed to /Applications/$(BUNDLE)"

clean:
	swift package clean
	rm -rf $(BUNDLE) .build
