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
 * Permission state used by the API 34+ photo picker contract. FULL is only
 * reported when READ_MEDIA_IMAGES itself is granted; selected photos alone
 * are an explicit PARTIAL state.
 */
enum class MediaAccessState {
    FULL,
    PARTIAL,
    DENIED,
}

/**
 * The prototype's complete Android permission and service contract. Keeping
 * the policy URL next to each allowed permission makes the evidence packet
 * auditable without treating a broad permission as an implementation detail.
 */
object GateKPermissionContract {
    const val READ_MEDIA_IMAGES = "android.permission.READ_MEDIA_IMAGES"
    const val READ_MEDIA_VISUAL_USER_SELECTED =
        "android.permission.READ_MEDIA_VISUAL_USER_SELECTED"
    const val MANAGE_EXTERNAL_STORAGE = "android.permission.MANAGE_EXTERNAL_STORAGE"
    const val BIND_INPUT_METHOD = "android.permission.BIND_INPUT_METHOD"
    const val BIND_ACCESSIBILITY_SERVICE = "android.permission.BIND_ACCESSIBILITY_SERVICE"
    const val INPUT_METHOD_ACTION = "android.view.InputMethod"

    private const val PHOTO_POLICY =
        "https://support.google.com/googleplay/android-developer/answer/16935362?hl=en"
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

    fun mediaAccessState(
        apiLevel: Int,
        readMediaImagesGranted: Boolean,
        readMediaVisualUserSelectedGranted: Boolean,
    ): MediaAccessState = when {
        // Android 14 precedence: the full image grant wins even if the
        // selected-photos bit is also reported by the package manager.
        apiLevel >= 34 && readMediaImagesGranted -> MediaAccessState.FULL
        apiLevel >= 34 && readMediaVisualUserSelectedGranted -> MediaAccessState.PARTIAL
        else -> MediaAccessState.DENIED
    }

    /** Returns true only for the full-image state used by Gate K. */
    fun hasFullMediaStoreImageGrant(
        apiLevel: Int,
        readMediaImagesGranted: Boolean,
        readMediaVisualUserSelectedGranted: Boolean,
    ): Boolean = mediaAccessState(
        apiLevel = apiLevel,
        readMediaImagesGranted = readMediaImagesGranted,
        readMediaVisualUserSelectedGranted = readMediaVisualUserSelectedGranted,
    ) == MediaAccessState.FULL

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
