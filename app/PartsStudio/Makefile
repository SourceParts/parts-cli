.PHONY: build run app clean

APP_NAME    := PartsStudio
BUILD_DIR   := .build/debug
APP_BUNDLE  := $(BUILD_DIR)/$(APP_NAME).app
ICON        := $(APP_NAME).icns
IDENTIFIER  := studio.source.parts

build:
	swift build

run: build
	$(BUILD_DIR)/$(APP_NAME)

app: build
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	@cp $(BUILD_DIR)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/
	@cp -r $(BUILD_DIR)/$(APP_NAME)_PartsStudio.bundle/FEL $(APP_BUNDLE)/Contents/Resources/ 2>/dev/null || true
	@cp -r $(BUILD_DIR)/$(APP_NAME)_PartsStudio.bundle/*.json $(APP_BUNDLE)/Contents/Resources/ 2>/dev/null || true
	@test -f $(ICON) && cp $(ICON) $(APP_BUNDLE)/Contents/Resources/ || true
	@echo '<?xml version="1.0" encoding="UTF-8"?>\n\
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n\
<plist version="1.0">\n\
<dict>\n\
	<key>CFBundleExecutable</key>\n\
	<string>$(APP_NAME)</string>\n\
	<key>CFBundleIdentifier</key>\n\
	<string>$(IDENTIFIER)</string>\n\
	<key>CFBundleIconFile</key>\n\
	<string>$(APP_NAME)</string>\n\
	<key>CFBundleName</key>\n\
	<string>$(APP_NAME)</string>\n\
	<key>CFBundlePackageType</key>\n\
	<string>APPL</string>\n\
	<key>CFBundleVersion</key>\n\
	<string>1.0</string>\n\
	<key>LSMinimumSystemVersion</key>\n\
	<string>14.0</string>\n\
	<key>NSHighResolutionCapable</key>\n\
	<true/>\n\
	<key>com.apple.security.device.usb</key>\n\
	<true/>\n\
</dict>\n\
</plist>' > $(APP_BUNDLE)/Contents/Info.plist
	@echo "Built $(APP_BUNDLE)"

install: app
	@rm -rf /Applications/$(APP_NAME).app
	@cp -r $(APP_BUNDLE) /Applications/
	@echo "Installed to /Applications/$(APP_NAME).app"

clean:
	swift package clean
