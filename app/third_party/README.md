# Vendored packages

| Package | Version | License | Why vendored |
|---|---|---|---|
| `pasteboard` | 0.5.0 | Apache-2.0 | Upstream's Android build applies the Kotlin Gradle Plugin unconditionally, which Flutter is deprecating ("Built-in Kotlin"). Patched `android/build.gradle` to apply it only when built-in Kotlin is off, via `project.pluginManager.apply(...)`. Drop this copy once upstream ships the fix. |
| `desktop_drop` | 0.8.4 | Apache-2.0 | Upstream already applies KGP only when needed, but with an `apply plugin:` line that Flutter's text-based detector flags. Patched to call `project.pluginManager.apply(...)` instead. |

In both, only `android/build.gradle` differs from upstream (and `example/`, `test/` were removed).
