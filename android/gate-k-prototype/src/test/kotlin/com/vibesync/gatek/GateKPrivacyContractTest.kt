package com.vibesync.gatek

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class GateKPrivacyContractTest {
    @Test
    fun `prototype allowlist accepts only the bounded screenshot read paths`() {
        val result = GateKPermissionContract.checkRequestedPermissions(
            listOf(
                GateKPermissionContract.READ_MEDIA_IMAGES,
                GateKPermissionContract.READ_EXTERNAL_STORAGE,
            ),
        )

        assertTrue(result.allowed)
        assertEquals(emptyList<String>(), result.violations)
        assertEquals(
            "https://support.google.com/googleplay/android-developer/answer/16558241?hl=en",
            GateKPermissionContract.allowedPermissionPolicies
                .single { it.permission == GateKPermissionContract.READ_MEDIA_IMAGES }
                .playPolicyUrl,
        )
        assertEquals(
            "https://support.google.com/googleplay/android-developer/answer/16558241?hl=en",
            GateKPermissionContract.allowedPermissionPolicies
                .single {
                    it.permission == GateKPermissionContract.READ_MEDIA_VISUAL_USER_SELECTED
                }
                .playPolicyUrl,
        )
        assertEquals(
            "https://support.google.com/googleplay/android-developer/answer/16935362?hl=en",
            GateKPermissionContract.MINIMUM_SCOPE_POLICY_URL,
        )
    }

    @Test
    fun `prototype rejects accessibility and broad storage permissions`() {
        val result = GateKPermissionContract.checkRequestedPermissions(
            listOf(
                GateKPermissionContract.READ_MEDIA_IMAGES,
                GateKPermissionContract.MANAGE_EXTERNAL_STORAGE,
                GateKPermissionContract.BIND_ACCESSIBILITY_SERVICE,
            ),
        )

        assertTrue(!result.allowed)
        assertEquals(
            listOf(
                GateKPermissionContract.MANAGE_EXTERNAL_STORAGE,
                GateKPermissionContract.BIND_ACCESSIBILITY_SERVICE,
            ),
            result.violations,
        )
    }

    @Test
    fun `prototype service contract is an InputMethodService and never an accessibility service`() {
        val result = GateKPermissionContract.checkServiceBinding(
            servicePermission = GateKPermissionContract.BIND_INPUT_METHOD,
            serviceAction = GateKPermissionContract.INPUT_METHOD_ACTION,
        )

        assertTrue(result.allowed)
        assertEquals(emptyList<String>(), result.violations)
    }

    @Test
    fun `accessibility service binding is rejected even with a valid input method action`() {
        val result = GateKPermissionContract.checkServiceBinding(
            servicePermission = GateKPermissionContract.BIND_ACCESSIBILITY_SERVICE,
            serviceAction = GateKPermissionContract.INPUT_METHOD_ACTION,
        )

        assertTrue(!result.allowed)
        assertEquals(
            listOf(GateKPermissionContract.BIND_ACCESSIBILITY_SERVICE),
            result.violations,
        )
    }

    @Test
    fun `partial selected photos state is never treated as a full image grant`() {
        assertTrue(
            !GateKPermissionContract.hasFullMediaStoreImageGrant(
                apiLevel = 34,
                readMediaImagesGranted = true,
                readMediaVisualUserSelectedGranted = true,
                readExternalStorageGranted = false,
            ),
        )
        assertTrue(
            GateKPermissionContract.hasFullMediaStoreImageGrant(
                apiLevel = 34,
                readMediaImagesGranted = true,
                readMediaVisualUserSelectedGranted = false,
                readExternalStorageGranted = false,
            ),
        )
    }

    @Test
    fun `legacy and modern full image grants use their API-specific permission`() {
        assertTrue(
            GateKPermissionContract.hasFullMediaStoreImageGrant(
                apiLevel = 33,
                readMediaImagesGranted = true,
                readMediaVisualUserSelectedGranted = false,
                readExternalStorageGranted = false,
            ),
        )
        assertTrue(
            GateKPermissionContract.hasFullMediaStoreImageGrant(
                apiLevel = 32,
                readMediaImagesGranted = false,
                readMediaVisualUserSelectedGranted = false,
                readExternalStorageGranted = true,
            ),
        )
        assertTrue(
            !GateKPermissionContract.hasFullMediaStoreImageGrant(
                apiLevel = 32,
                readMediaImagesGranted = false,
                readMediaVisualUserSelectedGranted = false,
                readExternalStorageGranted = false,
            ),
        )
    }
}
