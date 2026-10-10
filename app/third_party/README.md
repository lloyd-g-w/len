# Vendored packages

| Package | Version | License | Why vendored |
|---|---|---|---|
| `pasteboard` | 0.5.0 | Apache-2.0 | Upstream's Android build applies the Kotlin Gradle Plugin unconditionally, which Flutter is deprecating ("Built-in Kotlin"). Patched `android/build.gradle` to apply it only when AGP lacks built-in Kotlin (same approach as `desktop_drop`). Drop this copy once upstream ships the fix. |

Only `android/build.gradle` differs from upstream (and `example/`, `test/` were removed).
