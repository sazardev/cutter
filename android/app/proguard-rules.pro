# Classes the Rust side reaches by JNI name and signature. R8 renames the
# return types of the plugin's methods unless kept, and the native lookup
# `...getTextureRegistry(J)Lio/flutter/view/TextureRegistry;` then fails with
# NoSuchMethodError at launch (release builds only: profile does not shrink).
-keep class dev.irondash.** { *; }
-keep class io.flutter.view.TextureRegistry { *; }
-keep class io.flutter.plugin.common.BinaryMessenger { *; }
