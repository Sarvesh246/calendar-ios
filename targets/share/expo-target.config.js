/** @type {import('@bacons/apple-targets/app.plugin').ConfigFunction} */
module.exports = () => ({
  type: "share",
  name: "DatebookShare",
  deploymentTarget: "16.4",
  entitlements: {
    "com.apple.security.application-groups": ["group.com.sarveshjagtap.datebook"],
  },
});
