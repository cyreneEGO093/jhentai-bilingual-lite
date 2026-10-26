-keep class androidx.lifecycle.DefaultLifecycleObserver
# JNI looks up Java types by name, including result metadata/constructors.
# https://onnxruntime.ai/docs/build/android.html
-keep class ai.onnxruntime.** { *; }
-keep class org.opencv.** { *; }
