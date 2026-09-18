/** @type {import('@bacons/apple-targets/app.plugin').ConfigFunction} */
module.exports = (config) => ({
  type: "widget",
  name: "DatebookWidgets",
  deploymentTarget: "16.4",
  entitlements: {
    "com.apple.security.application-groups": ["group.com.sarveshjagtap.datebook"],
  },
  frameworks: ["SwiftUI", "WidgetKit", "ActivityKit"],
});
