# AfterFrame ProGuard/R8 规则
# 保留 FFmpeg Kit JNI 桥接类，防止 R8 在启用 minify 时误删

# FFmpeg Kit 核心包
-keep class com.antonkarpenko.ffmpegkit.** { *; }
-dontwarn com.antonkarpenko.ffmpegkit.**

# Smart Exception（FFmpeg Kit 的依赖）
-keep class com.arthenica.smartexception.** { *; }
-dontwarn com.arthenica.smartexception.**

# 保留所有 native 方法，防止 JNI 调用失败
-keepclasseswithmembernames class * {
    native <methods>;
}
