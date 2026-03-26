.PHONY: build sign run app clean

APP_NAME    := PartsStudio
BUILD_DIR   := .build/debug
APP_BUNDLE  := $(BUILD_DIR)/$(APP_NAME).app
ICON        := $(APP_NAME).icns
IDENTIFIER  := studio.source.parts
SIGN_ID     ?= PartsStudio Dev

build:
	swift build

sign: build
	@codesign --force --sign "$(SIGN_ID)" $(BUILD_DIR)/$(APP_NAME) 2>/dev/null \
		&& echo "Signed with '$(SIGN_ID)'" \
		|| echo "No signing identity '$(SIGN_ID)' — run unsigned (keychain prompts expected)"

run: sign
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
	<key>CFBundleDocumentTypes</key>\n\
	<array>\n\
		<dict>\n\
			<key>CFBundleTypeName</key>\n\
			<string>Gerber File</string>\n\
			<key>CFBundleTypeRole</key>\n\
			<string>Viewer</string>\n\
			<key>CFBundleTypeExtensions</key>\n\
			<array>\n\
				<string>gbr</string>\n\
				<string>gtl</string>\n\
				<string>gbl</string>\n\
				<string>gts</string>\n\
				<string>gbs</string>\n\
				<string>gto</string>\n\
				<string>gbo</string>\n\
				<string>gtp</string>\n\
				<string>gbp</string>\n\
				<string>gm1</string>\n\
				<string>gko</string>\n\
				<string>drl</string>\n\
				<string>xln</string>\n\
			</array>\n\
			<key>LSHandlerRank</key>\n\
			<string>Default</string>\n\
		</dict>\n\
		<dict>\n\
			<key>CFBundleTypeName</key>\n\
			<string>Gerber Job File</string>\n\
			<key>CFBundleTypeRole</key>\n\
			<string>Viewer</string>\n\
			<key>CFBundleTypeExtensions</key>\n\
			<array>\n\
				<string>gbrjob</string>\n\
			</array>\n\
			<key>LSHandlerRank</key>\n\
			<string>Owner</string>\n\
		</dict>\n\
		<dict>\n\
			<key>CFBundleTypeName</key>\n\
			<string>CSV File</string>\n\
			<key>CFBundleTypeRole</key>\n\
			<string>Viewer</string>\n\
			<key>CFBundleTypeExtensions</key>\n\
			<array>\n\
				<string>csv</string>\n\
			</array>\n\
			<key>LSHandlerRank</key>\n\
			<string>Alternate</string>\n\
		</dict>\n\
		<dict>\n\
			<key>CFBundleTypeName</key>\n\
			<string>DXF File</string>\n\
			<key>CFBundleTypeRole</key>\n\
			<string>Viewer</string>\n\
			<key>CFBundleTypeExtensions</key>\n\
			<array>\n\
				<string>dxf</string>\n\
			</array>\n\
			<key>LSHandlerRank</key>\n\
			<string>Alternate</string>\n\
		</dict>\n\
		<dict>\n\
			<key>CFBundleTypeName</key>\n\
			<string>STEP File</string>\n\
			<key>CFBundleTypeRole</key>\n\
			<string>Viewer</string>\n\
			<key>CFBundleTypeExtensions</key>\n\
			<array>\n\
				<string>step</string>\n\
				<string>stp</string>\n\
			</array>\n\
			<key>LSHandlerRank</key>\n\
			<string>Alternate</string>\n\
		</dict>\n\
		<dict>\n\
			<key>CFBundleTypeName</key>\n\
			<string>PDF Document</string>\n\
			<key>CFBundleTypeRole</key>\n\
			<string>Viewer</string>\n\
			<key>CFBundleTypeExtensions</key>\n\
			<array>\n\
				<string>pdf</string>\n\
			</array>\n\
			<key>LSHandlerRank</key>\n\
			<string>Alternate</string>\n\
		</dict>\n\
	</array>\n\
	<key>CFBundleURLTypes</key>\n\
	<array>\n\
		<dict>\n\
			<key>CFBundleURLName</key>\n\
			<string>Parts Studio</string>\n\
			<key>CFBundleURLSchemes</key>\n\
			<array>\n\
				<string>parts</string>\n\
			</array>\n\
		</dict>\n\
	</array>\n\
</dict>\n\
</plist>' > $(APP_BUNDLE)/Contents/Info.plist
	@codesign --force --sign "$(SIGN_ID)" $(APP_BUNDLE) 2>/dev/null \
		&& echo "Signed $(APP_BUNDLE) with '$(SIGN_ID)'" \
		|| echo "Warning: not signed (create cert named '$(SIGN_ID)' in Keychain Access)"
	@echo "Built $(APP_BUNDLE)"

install: app
	@rm -rf /Applications/$(APP_NAME).app
	@cp -r $(APP_BUNDLE) /Applications/
	@echo "Installed to /Applications/$(APP_NAME).app"

clean:
	swift package clean
