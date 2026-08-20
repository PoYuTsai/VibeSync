package com.vibesync.app

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.util.Log
import com.linusu.flutter_web_auth_2.FlutterWebAuth2Plugin

/**
 * 凍結 URI com.poyutsai.vibesync://login-callback 的唯一 manifest 擁有者。
 *
 * OAuth 與 email 深連結共用同一 URI，靠這裡分流而不是靠 host：
 * flutter_web_auth_2 有 live callback（OAuth 進行中）時把 URI 原字串交回
 * plugin（對齊其 CallbackActivity 的行為與收尾）；否則把未動過的 VIEW
 * intent/data 明確轉送給 singleTop MainActivity（冷啟走 onCreate、
 * 暖啟走 onNewIntent），由 app_links／supabase_flutter 接手。
 * 兩條路都是明確 component，不經 activity 選擇器（無 chooser）。
 * log 只記路由與 host，不記 query/fragment——token 不落 log。
 */
class AuthCallbackDispatcherActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val uri = intent?.data
        val liveCallback = uri?.scheme?.let { FlutterWebAuth2Plugin.callbacks.remove(it) }
        when {
            uri != null && liveCallback != null -> {
                Log.i(MainActivity.TAG, "dispatcher route=web-auth host=${uri.host ?: "none"}")
                liveCallback.success(uri.toString())
                // 偏離 pinned plugin CallbackActivity 的無條件 finishAndRemoveTask：
                // 只有本 activity 是 task root（task 裡只有自己）才可移除整個
                // task；否則（被 launch 進含 MainActivity 或 Custom Tab 的
                // 既有 task）只 finish 自己，絕不連帶清掉既有 app task。
                // 不額外把 app task 帶回前景：那會對 Main 送 VIEW intent，
                // 造成 app_links／supabase 對同一 URI 二次處理。
                if (isTaskRoot) finishAndRemoveTask() else finish()
            }
            uri != null -> {
                Log.i(MainActivity.TAG, "dispatcher route=main host=${uri.host ?: "none"}")
                startActivity(
                    Intent(Intent.ACTION_VIEW, uri, this, MainActivity::class.java)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
                )
                finish()
            }
            else -> {
                Log.i(MainActivity.TAG, "dispatcher route=drop host=none")
                finish()
            }
        }
    }
}
