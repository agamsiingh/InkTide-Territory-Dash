# shared_preferences_android 2.5.x calls into Kotlin from Dart over JNI (jnigen),
# looking classes and methods up by exact name/signature at runtime. R8 can't
# see those calls, so it strips or renames them and release builds crash on
# startup (NoSuchMethodError / ClassNotFoundException), leaving the app stuck
# on the splash screen. Keep the plugin plus every Kotlin runtime class the
# generated bindings reference (Continuation, CoroutineSingletons, Result, ...).
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-keep class kotlin.coroutines.** { *; }
-keep class kotlin.Result { *; }
-keep class kotlin.Result$Failure { *; }
-keep class kotlin.Unit { *; }
-keep class kotlin.enums.EnumEntries { *; }
-keep class kotlin.jvm.internal.DefaultConstructorMarker { *; }
