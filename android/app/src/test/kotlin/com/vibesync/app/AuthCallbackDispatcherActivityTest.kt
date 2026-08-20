package com.vibesync.app

import android.content.Intent
import android.net.Uri
import com.linusu.flutter_web_auth_2.FlutterWebAuth2Plugin
import io.flutter.plugin.common.MethodChannel
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * AND-03 deterministic seam 測試（P1-2）：不連外、不開瀏覽器，直接 seed
 * FlutterWebAuth2Plugin.callbacks 驗證 dispatcher 分流。凍結 URI
 * com.poyutsai.vibesync://login-callback 為契約，不得改。
 * Robolectric 釘 sdk 34（4.14.x 支援上限內），與裝置層行為的對拍由
 * install-smoke.sh 的 API 24／36 emulator 證據補齊。
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class AuthCallbackDispatcherActivityTest {
    private val scheme = "com.poyutsai.vibesync"
    private val frozenUri = "$scheme://login-callback#access_token=fake-not-a-secret"

    private class FakeResult : MethodChannel.Result {
        var successValue: Any? = null
        var successCount = 0
        override fun success(result: Any?) {
            successValue = result
            successCount++
        }
        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) =
            fail("不應走 error：$errorCode")
        override fun notImplemented() = fail("不應走 notImplemented")
    }

    @After
    fun tearDown() {
        FlutterWebAuth2Plugin.callbacks.clear()
    }

    @Test
    fun `live OAuth callback 原字串交回 plugin、移除 map、不轉送 MainActivity`() {
        val fake = FakeResult()
        FlutterWebAuth2Plugin.callbacks[scheme] = fake

        val activity = Robolectric.buildActivity(
            AuthCallbackDispatcherActivity::class.java,
            Intent(Intent.ACTION_VIEW, Uri.parse(frozenUri)),
        ).setup().get()

        assertEquals(frozenUri, fake.successValue)
        assertEquals(1, fake.successCount)
        assertTrue(
            "callback 應已從 map 移除",
            !FlutterWebAuth2Plugin.callbacks.containsKey(scheme),
        )
        assertNull(
            "OAuth 分支不得走 Main fallback",
            shadowOf(activity).nextStartedActivity,
        )
        assertTrue(activity.isFinishing)
    }

    @Test
    fun `無 live callback 時原樣轉送 singleTop MainActivity`() {
        val activity = Robolectric.buildActivity(
            AuthCallbackDispatcherActivity::class.java,
            Intent(Intent.ACTION_VIEW, Uri.parse(frozenUri)),
        ).setup().get()

        val forwarded = shadowOf(activity).nextStartedActivity
            ?: return fail("應轉送 MainActivity")
        assertEquals(MainActivity::class.java.name, forwarded.component?.className)
        assertEquals(Uri.parse(frozenUri), forwarded.data)
        assertEquals(Intent.ACTION_VIEW, forwarded.action)
        assertTrue(forwarded.flags and Intent.FLAG_ACTIVITY_NEW_TASK != 0)
        assertTrue(forwarded.flags and Intent.FLAG_ACTIVITY_SINGLE_TOP != 0)
        assertTrue(activity.isFinishing)
    }

    @Test
    fun `無 data 時直接收掉、不轉送也不碰 plugin`() {
        val fake = FakeResult()
        FlutterWebAuth2Plugin.callbacks[scheme] = fake

        val activity = Robolectric.buildActivity(
            AuthCallbackDispatcherActivity::class.java,
            Intent(Intent.ACTION_VIEW),
        ).setup().get()

        assertEquals(0, fake.successCount)
        assertTrue(FlutterWebAuth2Plugin.callbacks.containsKey(scheme))
        assertNull(shadowOf(activity).nextStartedActivity)
        assertTrue(activity.isFinishing)
    }
}
