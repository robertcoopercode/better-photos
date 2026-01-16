#!/bin/bash
# Auto-rebuild and run BetterPhotos when Swift files change

PROJECT_DIR="/Users/robertcooper/Projects/better-photos"
PROJECT="$PROJECT_DIR/BetterPhotos.xcodeproj"
SCHEME="BetterPhotos"
APP_NAME="BetterPhotos"
BUILD_DIR="$PROJECT_DIR/build"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

build_and_run() {
    echo -e "${YELLOW}Building...${NC}"

    # Build the project (uses team from project settings)
    xcodebuild -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration Debug \
        -derivedDataPath "$BUILD_DIR" \
        -allowProvisioningUpdates \
        build 2>&1 | grep -E "(error:|warning:|BUILD SUCCEEDED|BUILD FAILED)"

    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        echo -e "${GREEN}Build succeeded!${NC}"

        # Kill existing instance
        pkill -x "$APP_NAME" 2>/dev/null

        # Find and run the app
        APP_PATH=$(find "$BUILD_DIR" -name "$APP_NAME.app" -type d | head -1)
        if [ -n "$APP_PATH" ]; then
            echo -e "${GREEN}Launching $APP_NAME...${NC}"
            open "$APP_PATH"
        else
            echo -e "${RED}Could not find built app${NC}"
        fi
    else
        echo -e "${RED}Build failed!${NC}"
    fi
}

echo "Watching for changes in $PROJECT_DIR/BetterPhotos/Sources..."
echo "Press Ctrl+C to stop"
echo ""

# Initial build
build_and_run

# Watch for changes
fswatch -o "$PROJECT_DIR/BetterPhotos/Sources" | while read; do
    echo ""
    echo -e "${YELLOW}Change detected...${NC}"
    sleep 0.5  # Debounce multiple rapid changes
    build_and_run
done
