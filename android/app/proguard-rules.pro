# Suppress Play Core warnings (referenced by Flutter deferred components)
-dontwarn com.google.android.play.core.**

# Flutter & Plugin MethodChannels / Pigeon APIs (fixes NoSuchMethodError on plugins in release)
-keep class io.flutter.** { *; }
-keep interface io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep interface io.flutter.plugins.** { *; }

# Keep Firebase Components & Services
-dontwarn com.google.firebase.**
-keep class com.google.firebase.** { *; }
-keep interface com.google.firebase.** { *; }
-keep class * implements com.google.firebase.components.ComponentRegistrar { *; }

# Suppress missing classes from unused language recognizers
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
-dontwarn com.google.mlkit.**

# Keep ML Kit internal implementations, models, and providers
-keep class com.google.mlkit.** { *; }
-keep interface com.google.mlkit.** { *; }
-keep class * extends com.google.mlkit.common.sdkinternal.ModelResource { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }
-keep class com.google.android.datatransport.** { *; }

# Prevent obfuscation of names for dynamically loaded classes & native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

-keepclassmembers public class * extends android.app.Service {
    public <init>();
}
