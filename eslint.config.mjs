import { defineConfig, globalIgnores } from "eslint/config";
import expoConfig from "eslint-config-expo/flat.js";

const config = defineConfig([
  expoConfig,
  {
    // The React Compiler rules misread Animated.Value kept in useRef (the standard
    // React Native pattern), so they warn here instead of failing the build.
    rules: {
      "react-hooks/refs": "warn",
      "react-hooks/set-state-in-effect": "warn",
    },
  },
  globalIgnores([
    "dist/**",
    "dist-live-activity/**",
    ".expo/**",
    "ios/**",
    "android/**",
    "graphify-out/**",
  ]),
]);

export default config;
