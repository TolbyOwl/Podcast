# Android ProGuard rules for release builds
# Add rules to prevent R8 from obfuscating or removing audio_service and media_kit classes

# Keep audio_service classes
-keep class com.ryanheise.audioservice.** { *; }

# Keep media_kit classes
-keep class com.media_kit.** { *; }

# Keep attributes for reflection
-keepattributes *Annotation*,Signature
