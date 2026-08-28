package com.vibesync.gatek

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class GateKDeviceClassifierTest {
    @Test
    fun `explicit emulator markers classify as emulator`() {
        val descriptor = descriptor(
            manufacturer = "Google",
            brand = "google",
            model = "sdk_gphone64_x86_64",
            product = "sdk_gphone64_x86_64",
            fingerprint = "google/sdk_gphone64_x86_64/emulator",
        )

        assertEquals(GateKDeviceClass.EMULATOR, GateKDeviceClassifier.classify(descriptor))
    }

    @Test
    fun `physical Samsung is classified only from raw Samsung fields`() {
        val descriptor = descriptor(
            manufacturer = "samsung",
            brand = "samsung",
            model = "SM-S938B",
            product = "e3qxxx",
            fingerprint = "samsung/e3qxxx/e3q:14/UP1A/release-keys",
        )

        assertEquals(GateKDeviceClass.PHYSICAL_SAMSUNG, GateKDeviceClassifier.classify(descriptor))
    }

    @Test
    fun `explicit emulator signal wins over a Samsung-looking caller descriptor`() {
        val descriptor = descriptor(
            manufacturer = "samsung",
            brand = "samsung",
            model = "Android SDK built for x86_64",
            product = "sdk_gphone_x86_64",
            fingerprint = "generic/sdk/generic_x86_64:14/UE1A/test-keys",
        )

        assertEquals(GateKDeviceClass.EMULATOR, GateKDeviceClassifier.classify(descriptor))
    }

    @Test
    fun `unknown raw descriptor remains unclassified and canonical output is complete`() {
        val descriptor = descriptor(
            manufacturer = "Acme",
            brand = "acme",
            model = "Model-1",
            product = "product-1",
            fingerprint = "acme/product/release-keys",
        )

        assertEquals(GateKDeviceClass.UNCLASSIFIED, GateKDeviceClassifier.classify(descriptor))
        val canonical = descriptor.canonical()
        assertTrue(canonical.contains("manufacturer=Acme"))
        assertTrue(canonical.contains("fingerprint=acme/product/release-keys"))
        assertTrue(canonical.contains("api=34"))
    }

    private fun descriptor(
        manufacturer: String,
        brand: String,
        model: String,
        product: String,
        fingerprint: String,
    ) = GateKDeviceDescriptor(
        manufacturer = manufacturer,
        brand = brand,
        model = model,
        product = product,
        fingerprint = fingerprint,
        apiLevel = 34,
    )
}
