# Keep kotlinx.serialization generated serializers for our models.
-keepclassmembers class com.fuseos.app.data.** {
    *** Companion;
}
-keepclasseswithmembers class com.fuseos.app.data.** {
    kotlinx.serialization.KSerializer serializer(...);
}
