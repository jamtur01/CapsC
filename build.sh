#!/bin/bash

# CapsC Build Script
# Builds and optionally signs/notarizes the CapsC macOS application

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PROJECT_NAME="CapsC"
SCHEME_NAME="CapsC"
BUNDLE_ID="net.kartar.CapsC"
BUILD_DIR="build"

# Default values
BUILD_CONFIG="Release"
QUICK_BUILD=false
SIGN_BUILD=false
NOTARIZE=false
OPEN_AFTER_BUILD=false
RUN_AFTER_BUILD=false

usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Quick build (no code signing):"
    echo "  $0 --quick                      Quick Debug build"
    echo "  $0 --quick --release            Quick Release build"
    echo ""
    echo "Production build (with code signing):"
    echo "  $0 --sign                       Build and sign for local distribution"
    echo "  $0 --sign --notarize            Build, sign, and notarize for distribution"
    echo ""
    echo "Options:"
    echo "  -q, --quick                     Quick build without code signing"
    echo "  -s, --sign                      Build with code signing"
    echo "  -n, --notarize                  Notarize the app (requires --sign)"
    echo "  -r, --release                   Use Release configuration (default for signed builds)"
    echo "  -d, --debug                     Use Debug configuration (default for quick builds)"
    echo "  -o, --open                      Open build folder after completion"
    echo "  -x, --run                       Run the app after building"
    echo "  -h, --help                      Show this help message"
    echo ""
    echo "Notarization options (required when using --notarize):"
    echo "  --developer-id <ID>             Developer ID Application certificate name"
    echo "  --team-id <ID>                  Team ID for notarization"
    echo "  --apple-id <email>              Apple ID for notarization"
    echo "  --app-password <password>       App-specific password for notarization"
    echo ""
    echo "Examples:"
    echo "  $0 --quick                      # Quick local build"
    echo "  $0 --quick --release --run      # Quick Release build and run"
    echo "  $0 --sign                       # Signed build for local testing"
    echo "  $0 --sign --notarize --developer-id \"Developer ID Application: Your Name (TEAMID)\" \\"
    echo "     --team-id TEAMID --apple-id your@email.com --app-password xxxx-xxxx-xxxx-xxxx"
}

# Parse command line arguments
DEVELOPER_ID=""
TEAM_ID=""
APPLE_ID=""
APP_PASSWORD=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -q|--quick)
            QUICK_BUILD=true
            shift
            ;;
        -s|--sign)
            SIGN_BUILD=true
            shift
            ;;
        -n|--notarize)
            NOTARIZE=true
            SIGN_BUILD=true
            shift
            ;;
        -r|--release)
            BUILD_CONFIG="Release"
            shift
            ;;
        -d|--debug)
            BUILD_CONFIG="Debug"
            shift
            ;;
        -o|--open)
            OPEN_AFTER_BUILD=true
            shift
            ;;
        -x|--run)
            RUN_AFTER_BUILD=true
            shift
            ;;
        --developer-id)
            DEVELOPER_ID="$2"
            shift 2
            ;;
        --team-id)
            TEAM_ID="$2"
            shift 2
            ;;
        --apple-id)
            APPLE_ID="$2"
            shift 2
            ;;
        --app-password)
            APP_PASSWORD="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            exit 1
            ;;
    esac
done

# Validate options
if [[ "$QUICK_BUILD" == false && "$SIGN_BUILD" == false ]]; then
    echo -e "${RED}Error: Must specify either --quick or --sign${NC}"
    usage
    exit 1
fi

if [[ "$QUICK_BUILD" == true && "$SIGN_BUILD" == true ]]; then
    echo -e "${RED}Error: Cannot use both --quick and --sign${NC}"
    usage
    exit 1
fi

if [[ "$NOTARIZE" == true ]]; then
    if [[ -z "$DEVELOPER_ID" || -z "$TEAM_ID" || -z "$APPLE_ID" || -z "$APP_PASSWORD" ]]; then
        echo -e "${RED}Error: Notarization requires --developer-id, --team-id, --apple-id, and --app-password${NC}"
        exit 1
    fi
fi

# Set default build config based on build type
if [[ "$QUICK_BUILD" == true && "$BUILD_CONFIG" != "Release" ]]; then
    BUILD_CONFIG="Debug"
elif [[ "$SIGN_BUILD" == true && "$BUILD_CONFIG" != "Debug" ]]; then
    BUILD_CONFIG="Release"
fi

echo -e "${BLUE}=== CapsC Build Script ===${NC}"
echo -e "${BLUE}Build Type: $([ "$QUICK_BUILD" == true ] && echo "Quick" || echo "Production")${NC}"
echo -e "${BLUE}Configuration: ${BUILD_CONFIG}${NC}"
echo -e "${BLUE}Code Signing: $([ "$SIGN_BUILD" == true ] && echo "Yes" || echo "No")${NC}"
echo -e "${BLUE}Notarize: $([ "$NOTARIZE" == true ] && echo "Yes" || echo "No")${NC}"
echo ""

# Quick build
if [[ "$QUICK_BUILD" == true ]]; then
    OUTPUT_DIR="${BUILD_DIR}/${BUILD_CONFIG}"
    
    # Clean build directory
    echo -e "${YELLOW}Cleaning build directory...${NC}"
    rm -rf "${OUTPUT_DIR}"
    mkdir -p "${OUTPUT_DIR}"
    
    # Build without code signing
    echo -e "${YELLOW}Building ${PROJECT_NAME} (quick build)...${NC}"
    xcodebuild \
        -project "${PROJECT_NAME}.xcodeproj" \
        -scheme "${SCHEME_NAME}" \
        -configuration "${BUILD_CONFIG}" \
        -derivedDataPath "${BUILD_DIR}/DerivedData" \
        CONFIGURATION_BUILD_DIR="${OUTPUT_DIR}" \
        CODE_SIGN_IDENTITY="" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO
    
    APP_PATH="${OUTPUT_DIR}/${PROJECT_NAME}.app"
else
    # Production build with signing
    ARCHIVE_PATH="${BUILD_DIR}/${PROJECT_NAME}.xcarchive"
    EXPORT_PATH="${BUILD_DIR}/Export"
    EXPORT_OPTIONS_PLIST="${BUILD_DIR}/ExportOptions.plist"
    
    # Clean build directory
    echo -e "${YELLOW}Cleaning build directory...${NC}"
    rm -rf "${BUILD_DIR}"
    mkdir -p "${BUILD_DIR}"
    
    # Clean Xcode build
    echo -e "${YELLOW}Cleaning Xcode build...${NC}"
    xcodebuild clean \
        -project "${PROJECT_NAME}.xcodeproj" \
        -scheme "${SCHEME_NAME}" \
        -configuration "${BUILD_CONFIG}"
    
    # Build archive
    echo -e "${YELLOW}Building archive...${NC}"
    xcodebuild archive \
        -project "${PROJECT_NAME}.xcodeproj" \
        -scheme "${SCHEME_NAME}" \
        -configuration "${BUILD_CONFIG}" \
        -archivePath "${ARCHIVE_PATH}" \
        ONLY_ACTIVE_ARCH=NO
    
    # Create export options plist
    echo -e "${YELLOW}Creating export options...${NC}"
    if [[ -n "$DEVELOPER_ID" ]]; then
        # For notarized builds, use Developer ID
        cat > "${EXPORT_OPTIONS_PLIST}" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
    <key>signingCertificate</key>
    <string>${DEVELOPER_ID}</string>
    <key>signingStyle</key>
    <string>manual</string>
</dict>
</plist>
EOF
    else
        # For local builds, use automatic signing
        cat > "${EXPORT_OPTIONS_PLIST}" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>development</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
EOF
    fi
    
    # Export archive
    echo -e "${YELLOW}Exporting archive...${NC}"
    xcodebuild -exportArchive \
        -archivePath "${ARCHIVE_PATH}" \
        -exportPath "${EXPORT_PATH}" \
        -exportOptionsPlist "${EXPORT_OPTIONS_PLIST}"
    
    APP_PATH="${EXPORT_PATH}/${PROJECT_NAME}.app"
    
    # Verify code signature
    echo -e "${YELLOW}Verifying code signature...${NC}"
    codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
    
    # Display signature information
    echo -e "${YELLOW}Signature information:${NC}"
    codesign -dv --verbose=4 "${APP_PATH}"
    
    # Notarize if requested
    if [[ "$NOTARIZE" == true ]]; then
        echo -e "${YELLOW}Starting notarization process...${NC}"
        
        # Create a ZIP file for notarization
        ZIP_PATH="${BUILD_DIR}/${PROJECT_NAME}.zip"
        echo -e "${YELLOW}Creating ZIP file for notarization...${NC}"
        ditto -c -k --keepParent "${APP_PATH}" "${ZIP_PATH}"
        
        # Submit for notarization
        echo -e "${YELLOW}Submitting app for notarization...${NC}"
        xcrun notarytool submit "${ZIP_PATH}" \
            --apple-id "${APPLE_ID}" \
            --password "${APP_PASSWORD}" \
            --team-id "${TEAM_ID}" \
            --wait
        
        # Staple the notarization ticket
        echo -e "${YELLOW}Stapling notarization ticket...${NC}"
        xcrun stapler staple "${APP_PATH}"
        
        # Verify notarization
        echo -e "${YELLOW}Verifying notarization...${NC}"
        xcrun stapler validate "${APP_PATH}"
        
        # Create a notarized DMG (optional)
        DMG_PATH="${BUILD_DIR}/${PROJECT_NAME}.dmg"
        echo -e "${YELLOW}Creating DMG...${NC}"
        create-dmg \
            --volname "${PROJECT_NAME}" \
            --window-pos 200 120 \
            --window-size 600 400 \
            --icon-size 100 \
            --icon "${PROJECT_NAME}.app" 175 190 \
            --hide-extension "${PROJECT_NAME}.app" \
            --app-drop-link 425 190 \
            "${DMG_PATH}" \
            "${EXPORT_PATH}/" || {
            # Fallback to simple DMG creation if create-dmg is not installed
            echo -e "${YELLOW}create-dmg not found, using hdiutil instead...${NC}"
            hdiutil create -volname "${PROJECT_NAME}" -srcfolder "${EXPORT_PATH}" -ov -format UDZO "${DMG_PATH}"
        }
        
        echo -e "${GREEN}Notarization completed successfully!${NC}"
        echo -e "${BLUE}DMG file: ${DMG_PATH}${NC}"
    fi
fi

# Success message
echo -e "${GREEN}Build completed successfully!${NC}"
echo -e "${BLUE}App location: ${APP_PATH}${NC}"

# Open build folder if requested
if [[ "$OPEN_AFTER_BUILD" == true ]]; then
    echo -e "${YELLOW}Opening build folder...${NC}"
    open "$(dirname "${APP_PATH}")"
fi

# Run the app if requested
if [[ "$RUN_AFTER_BUILD" == true ]]; then
    echo -e "${YELLOW}Running ${PROJECT_NAME}...${NC}"
    open "${APP_PATH}"
fi

echo -e "${GREEN}=== Build script completed ===${NC}"