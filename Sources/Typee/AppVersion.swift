// MARK: - App version
// Single source of truth — build-app.sh and release.sh read the version from here.
let kAppVersion = "1.0.0"

// MARK: - Update check
// Points at a raw JSON file containing {"version":"x.y.z","url":"https://..."}.
// release.sh keeps latest.json in sync on every release.
// Set to nil to disable automatic update checks.
let kUpdateCheckURL: String? =
    "https://raw.githubusercontent.com/ReyanshNangia/typee-app/main/latest.json"
