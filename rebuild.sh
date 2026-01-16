#!/bin/bash
# Rebuild and restart BetterPhotos

cd /Users/robertcooper/Projects/better-photos

# Build
OUTPUT=$(xcodebuild -project BetterPhotos.xcodeproj -scheme BetterPhotos -configuration Debug -derivedDataPath build -allowProvisioningUpdates build 2>&1)

# Check result
if echo "$OUTPUT" | grep -q "BUILD SUCCEEDED"; then
    echo "BUILD SUCCEEDED"
    pkill -x BetterPhotos 2>/dev/null
    sleep 0.3
    open build/Build/Products/Debug/BetterPhotos.app
    echo "App launched"
else
    echo "BUILD FAILED"
    echo "$OUTPUT" | grep -E "(error:)" | head -10
fi
