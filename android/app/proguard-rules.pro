# Flutter and its plugins ship their own consumer ProGuard/R8 rules, so only
# app-specific keep rules go here.

# Keep androidx's edge-to-edge entry point as a real call site in MainActivity.
# R8 would otherwise inline enableEdgeToEdge() and rename its class, leaving no
# EdgeToEdge.enable call for Play Console's edge-to-edge check to find.
-keep class androidx.activity.EdgeToEdge {
    public static *** enable(...);
}
