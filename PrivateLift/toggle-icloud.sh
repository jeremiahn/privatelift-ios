#!/bin/bash

# Script to easily toggle iCloud/CloudKit entitlements on/off.
# This helps developers build and test on physical devices using personal (free) Apple developer accounts,
# since Apple blocks custom CloudKit containers on personal development profiles.

# Smart path resolution for iOS entitlements
if [ -f "PrivateLift/PrivateLift.entitlements" ]; then
    ENTITLEMENTS_FILE="PrivateLift/PrivateLift.entitlements"
elif [ -f "PrivateLift.entitlements" ]; then
    ENTITLEMENTS_FILE="PrivateLift.entitlements"
elif [ -f "../PrivateLift/PrivateLift.entitlements" ]; then
    ENTITLEMENTS_FILE="../PrivateLift/PrivateLift.entitlements"
else
    echo "Error: Could not find PrivateLift.entitlements"
    exit 1
fi

# Smart path resolution for watchOS entitlements
if [ -f "PrivateLiftWatch/PersonalLiftWatch.entitlements" ]; then
    WATCH_ENTITLEMENTS_FILE="PrivateLiftWatch/PersonalLiftWatch.entitlements"
elif [ -f "../PrivateLiftWatch/PersonalLiftWatch.entitlements" ]; then
    WATCH_ENTITLEMENTS_FILE="../PrivateLiftWatch/PersonalLiftWatch.entitlements"
else
    WATCH_ENTITLEMENTS_FILE=""
fi

if [ "$1" == "off" ]; then
    echo "Stripping iCloud/CloudKit entitlements for Personal Development Team..."
    
    # iOS entitlements
    cat <<EOF > "$ENTITLEMENTS_FILE"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.developer.healthkit</key>
	<true/>
</dict>
</plist>
EOF

    # Watch entitlements
    if [ -n "$WATCH_ENTITLEMENTS_FILE" ] && [ -f "$WATCH_ENTITLEMENTS_FILE" ]; then
        cat <<EOF > "$WATCH_ENTITLEMENTS_FILE"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.developer.healthkit</key>
	<true/>
</dict>
</plist>
EOF
        echo "Stripped iCloud entitlements from watchOS app."
    fi

    echo "Done! You can now sign and run the app on your physical device using your Personal Team."
elif [ "$1" == "on" ]; then
    echo "Restoring iCloud/CloudKit entitlements for Paid/Developer Team..."
    
    # iOS entitlements
    cat <<EOF > "$ENTITLEMENTS_FILE"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.developer.healthkit</key>
	<true/>
	<key>com.apple.developer.icloud-container-identifiers</key>
	<array>
		<string>iCloud.Nelson-Computers.PrivateLift</string>
	</array>
	<key>com.apple.developer.icloud-services</key>
	<array>
		<string>CloudKit</string>
		<string>CloudDocuments</string>
	</array>
	<key>com.apple.developer.ubiquity-container-identifiers</key>
	<array>
		<string>iCloud.Nelson-Computers.PrivateLift</string>
	</array>
</dict>
</plist>
EOF

    # Watch entitlements
    if [ -n "$WATCH_ENTITLEMENTS_FILE" ] && [ -f "$WATCH_ENTITLEMENTS_FILE" ]; then
        cat <<EOF > "$WATCH_ENTITLEMENTS_FILE"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.developer.healthkit</key>
	<true/>
	<key>com.apple.developer.icloud-container-identifiers</key>
	<array>
		<string>iCloud.Nelson-Computers.PrivateLift</string>
	</array>
	<key>com.apple.developer.icloud-services</key>
	<array>
		<string>CloudKit</string>
		<string>CloudDocuments</string>
	</array>
	<key>com.apple.developer.ubiquity-container-identifiers</key>
	<array>
		<string>iCloud.Nelson-Computers.PrivateLift</string>
	</array>
</dict>
</plist>
EOF
        echo "Restored iCloud entitlements to watchOS app."
    fi

    echo "Done! iCloud entitlements restored."
else
    echo "Usage: ./toggle-icloud.sh [on|off]"
fi
