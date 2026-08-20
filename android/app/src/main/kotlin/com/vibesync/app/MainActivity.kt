package com.vibesync.app

import android.content.Intent
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    // 深連結路由證據（install smoke 對拍用）：只記路由與 host，
    // 不記 query/fragment——token 不落 log。
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.i(TAG, "MainActivity route=cold host=${intent?.data?.host ?: "none"}")
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        Log.i(TAG, "MainActivity route=warm host=${intent.data?.host ?: "none"}")
    }

    companion object {
        const val TAG = "VibeSyncAuthRoute"
    }
}
