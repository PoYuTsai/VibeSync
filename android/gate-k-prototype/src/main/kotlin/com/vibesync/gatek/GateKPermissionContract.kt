package com.vibesync.gatek

data class GateKPolicyCheck(
    val allowed: Boolean,
    val violations: List<String>,
)

data class GateKPermissionPolicy(
    val permission: String,
    val maxSdk: Int?,
    val purpose: String,
    val playPolicyUrl: String,
)

/**
 * The prototype's complete Android permission and service contract. Keeping
 * the policy URL next to each allowed permission makes the evidence packet
 * auditable without treating a broad permission as an implementation detail.
 */
object GateKPermissionContract {
    const val READ_MEDIA_IMAGES = "android.permission.READ_MEDIA_IMAGES"
    const val READ_MEDIA_VISUAL_USER_SELECTED =
        "android.permission.READ_MEDIA_VISUAL_USER_SELECTED"
    const val READ_EXTERNAL_STORAGE = "android.permission.READ_EXTERNAL_STORAGE"
    const val MANAGE_EXTERNAL_STORAGE = "android.permission.MANAGE_EXTERNAL_STORAGE"
    const val BIND_INPUT_METHOD = "android.permission.BIND_INPUT_METHOD"
    const val BIND_ACCESSIBILITY_SERVICE = "android.permission.BIND_ACCESSIBILITY_SERVICE"
    const val INPUT_METHOD_ACTION = "android.view.InputMethod"

    private const val PHOTO_POLICY =
        "https://support.google.com/googleplay/android-developer/answer/16558241?hl=en"
    const val MINIMUM_SCOPE_POLICY_URL =
        "https://support.google.com/googleplay/android-developer/answer/16935362?hl=en"

    val allowedPermissionPolicies: List<GateKPermissionPolicy> = listOf(
        GateKPermissionPolicy(
            permission = READ_MEDIA_IMAGES,
            maxSdk = null,
            purpose = "Observe screenshot candidates through MediaStore only",
            playPolicyUrl = PHOTO_POLICY,
        ),
        GateKPermissionPolicy(
            permission = READ_MEDIA_VISUAL_USER_SELECTED,
            maxSdk = null,
            purpose = "Detect selected-photos partial state; never use it as screenshot source",
            playPolicyUrl = PHOTO_POLICY,
        ),
        GateKPermissionPolicy(
            permission = READ_EXTERNAL_STORAGE,
            maxSdk = 32,
            purpose = "Legacy MediaStore screenshot observation on API 32 and below",
            playPolicyUrl = PHOTO_POLICY,
        ),
    )

    private val allowedPermissions = allowedPermissionPolicies.map { it.permission }.toSet()

    fun checkRequestedPermissions(requestedPermissions: Collection<String>): GateKPolicyCheck {
        val violations = requestedPermissions
            .filter { it !in allowedPermissions }
            .distinct()
        return GateKPolicyCheck(
            allowed = violations.isEmpty(),
            violations = violations,
        )
    }

    /**
     * Returns true only for the API-specific full-image grant used by the
     * prototype. On API 34+, a granted visual-user-selected permission is the
     * system's partial-selection state, so READ_MEDIA_IMAGES alone is not
     * evidence of full MediaStore visibility.
     */
    fun hasFullMediaStoreImageGrant(
        apiLevel: Int,
        readMediaImagesGranted: Boolean,
        readMediaVisualUserSelectedGranted: Boolean,
        readExternalStorageGranted: Boolean,
    ): Boolean = when {
        apiLevel >= 34 -> readMediaImagesGranted && !readMediaVisualUserSelectedGranted
        apiLevel >= 33 -> readMediaImagesGranted
        else -> readExternalStorageGranted
    }

    fun checkServiceBinding(
        servicePermission: String?,
        serviceAction: String?,
    ): GateKPolicyCheck {
        val violations = buildList {
            if (servicePermission != BIND_INPUT_METHOD) {
                add(servicePermission ?: "missing-service-permission")
            }
            if (serviceAction != INPUT_METHOD_ACTION) {
                add(serviceAction ?: "missing-service-action")
            }
        }
        return GateKPolicyCheck(
            allowed = violations.isEmpty(),
            violations = violations,
        )
    }
}
