import Cocoa

let app = NSRunningApplication.runningApplicationsWithBundleIdentifier("com.apple.finder")

app[0].localizedName

String(format: "%2.0f%%", 1.0)