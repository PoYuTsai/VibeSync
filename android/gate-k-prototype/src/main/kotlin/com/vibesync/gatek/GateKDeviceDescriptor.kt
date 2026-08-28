package com.vibesync.gatek

import android.os.Build

/** Raw runtime descriptor retained as metadata; it never proves stock OEM behavior. */
data class GateKDeviceDescriptor(
    val manufacturer: String,
    val brand: String,
    val model: String,
    val product: String,
    val fingerprint: String,
    val apiLevel: Int,
) {
    companion object {
        fun fromBuild(): GateKDeviceDescriptor = GateKDeviceDescriptor(
            manufacturer = Build.MANUFACTURER.orEmpty(),
            brand = Build.BRAND.orEmpty(),
            model = Build.MODEL.orEmpty(),
            product = Build.PRODUCT.orEmpty(),
            fingerprint = Build.FINGERPRINT.orEmpty(),
            apiLevel = Build.VERSION.SDK_INT,
        )
    }

    /** Stable key order for deterministic metadata-only evidence. */
    fun canonical(): String = listOf(
        "manufacturer=$manufacturer",
        "brand=$brand",
        "model=$model",
        "product=$product",
        "fingerprint=$fingerprint",
        "api=$apiLevel",
    ).joinToString(separator = "|")
}

/** Conservative classifier; explicit emulator markers take precedence. */
object GateKDeviceClassifier {
    fun classify(descriptor: GateKDeviceDescriptor): GateKDeviceClass {
        val signals = listOf(
            descriptor.manufacturer,
            descriptor.brand,
            descriptor.model,
            descriptor.product,
            descriptor.fingerprint,
        ).map(String::lowercase)
        val explicitEmulator = signals.any { value ->
            value == "generic"
                || value.startsWith("generic/")
                || value.startsWith("generic_")
                || value.contains("emulator")
                || value.contains("sdk_gphone")
                || value.contains("aosp_x86")
                || value.contains("aosp_cf")
                || value.contains("ranchu")
                || value.contains("goldfish")
        }
        if (explicitEmulator) return GateKDeviceClass.EMULATOR

        val samsung = signals.any { value ->
            value == "samsung" || value.startsWith("samsung ")
        }
        return if (samsung) {
            GateKDeviceClass.PHYSICAL_SAMSUNG
        } else {
            GateKDeviceClass.UNCLASSIFIED
        }
    }
}
