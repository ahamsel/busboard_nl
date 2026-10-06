package com.ahamsel.busboard_nl

import android.os.Bundle
import androidx.activity.enableEdgeToEdge
import io.flutter.embedding.android.FlutterFragmentActivity

// A FlutterFragmentActivity (a ComponentActivity) so it can call androidx's
// enableEdgeToEdge(): Android 15+ is edge-to-edge for target SDK 35+, and this
// opts older versions in too, the way Play Console asks. Flutter lays out
// under the transparent bars (SystemUiMode.edgeToEdge) using the insets.
class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
    }
}
