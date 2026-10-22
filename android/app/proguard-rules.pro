# The beta reports crashes through Crashlytics and nobody uploads the R8
# mapping yet, so readable Java and Kotlin names matter more than the few
# hundred KB that renaming saves. Turn this off once the mapping upload runs
# in CI (the Crashlytics Gradle plugin).
-dontobfuscate
-keepattributes SourceFile,LineNumberTable

# Classes the Rust side reaches by JNI name and signature. R8 renames the
# return types of the plugin's methods unless kept, and the native lookup
# `...getTextureRegistry(J)Lio/flutter/view/TextureRegistry;` then fails with
# NoSuchMethodError at launch (release builds only: profile does not shrink).
-keep class dev.irondash.** { *; }
-keep class io.flutter.view.TextureRegistry { *; }
-keep class io.flutter.plugin.common.BinaryMessenger { *; }

# Firebase Performance serializes its traces with protobuf-lite, which looks
# fields up by name. R8 renamed them and the SDK crashed on the first activity
# start ("Field name_ for yx0 not found"); keep its generated messages whole.
-keep class com.google.firebase.perf.** { *; }
-keepclassmembers class * extends com.google.protobuf.GeneratedMessageLite {
    <fields>;
}
