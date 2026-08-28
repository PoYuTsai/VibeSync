package com.vibesync.gatek

import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.inputmethodservice.InputMethodService
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class GateKPrototypeManifestTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun `prototype manifest has only allowlisted permissions and no accessibility service`() {
        val packageInfo = context.packageManager.getPackageInfo(
            context.packageName,
            PackageManager.GET_PERMISSIONS,
        )
        val requested = packageInfo.requestedPermissions?.toList().orEmpty()
        val permissionCheck = GateKPermissionContract.checkRequestedPermissions(requested)

        assertTrue(permissionCheck.allowed)
        assertTrue(requested.contains(GateKPermissionContract.READ_MEDIA_IMAGES))
        assertTrue(requested.contains(GateKPermissionContract.READ_MEDIA_VISUAL_USER_SELECTED))
        assertTrue(requested.none { it.contains("ACCESSIBILITY", ignoreCase = true) })
        assertTrue(requested.none { it == GateKPermissionContract.MANAGE_EXTERNAL_STORAGE })
    }

    @Test
    fun `prototype service is bound to InputMethodService contract only`() {
        val component = ComponentName(context, GateKPrototypeInputMethodService::class.java)
        val serviceInfo = context.packageManager.getServiceInfo(component, 0)

        assertEquals(GateKPermissionContract.BIND_INPUT_METHOD, serviceInfo.permission)
        assertTrue(serviceInfo.exported)
        assertFalse(serviceInfo.name.contains("AccessibilityService", ignoreCase = true))
        val serviceClass = Class.forName(serviceInfo.name, false, context.classLoader)
        assertTrue(InputMethodService::class.java.isAssignableFrom(serviceClass))

        val inputMethodServices = context.packageManager.queryIntentServices(
            Intent(InputMethodService.SERVICE_INTERFACE),
            PackageManager.MATCH_ALL,
        )
        assertNotNull(inputMethodServices.firstOrNull { info ->
            info.serviceInfo?.packageName == context.packageName
                && info.serviceInfo?.name == serviceInfo.name
        })
    }
}
