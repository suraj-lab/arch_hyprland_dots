-- Environment
hl.env("XCURSOR_SIZE", "24")
-- GTK theme comes from gsettings (quickshell/scripts/apply-theme.sh), not GTK_THEME.
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct") -- qt5ct reads the same variable for Qt5
