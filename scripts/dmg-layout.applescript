on run arguments
    set mountPath to item 1 of arguments
    set volumeFolder to POSIX file mountPath as alias
    tell application "Finder"
        open volumeFolder
        set targetWindow to container window of volumeFolder
        set current view of targetWindow to icon view
        set toolbar visible of targetWindow to false
        set statusbar visible of targetWindow to false
        set bounds of targetWindow to {240, 180, 900, 602}
        set viewOptions to icon view options of targetWindow
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 96
        set text size of viewOptions to 13
        set background picture of viewOptions to file ".background:background.png" of volumeFolder
        set position of item "Claude Codex Timer.app" of volumeFolder to {160, 195}
        set position of item "Applications" of volumeFolder to {500, 195}
        -- Keep implementation folders out of the layout when hidden files are shown.
        set position of item ".background" of volumeFolder to {900, 500}
        if exists item ".fseventsd" of volumeFolder then set position of item ".fseventsd" of volumeFolder to {1050, 500}
        update volumeFolder without registering applications
        delay 2
        close targetWindow
        delay 1
    end tell
end run
