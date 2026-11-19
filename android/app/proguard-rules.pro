# WorkManager / Room (ML Kit ve Play Services kullanıyor): R8'in oluşturulmuş veritabanı sınıflarını silmesini engelle
-keep class androidx.work.** { *; }
-keep class * extends androidx.room.RoomDatabase { *; }
-keep class androidx.room.** { *; }
-dontwarn androidx.room.paging.**
# ML Kit Digital Ink
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_digital_ink.** { *; }
-dontwarn com.google.mlkit.**
# Google Sign-In
-keep class com.google.android.gms.auth.** { *; }
