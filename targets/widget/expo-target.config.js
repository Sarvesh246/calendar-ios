/** @type {import('@bacons/apple-targets/app.plugin').ConfigFunction} */
module.exports = (config) => ({
  type: "widget",
  name: "DatebookWidgets",
  displayName: "Datebook",
  deploymentTarget: "16.4",
  colors: {
    $accent: "#0A84FF",
    $widgetBackground: "#07070a",
  },
  entitlements: {
    "com.apple.security.application-groups": ["group.com.sarveshjagtap.datebook"],
  },
  frameworks: ["SwiftUI", "WidgetKit", "ActivityKit"],
});
