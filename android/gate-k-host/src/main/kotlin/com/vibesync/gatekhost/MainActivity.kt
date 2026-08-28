package com.vibesync.gatekhost

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.WindowManager
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView

/** Disposable foreground text host used only to make the IME surface visible. */
class MainActivity : Activity() {
    private lateinit var nonceLabel: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val editor = EditText(this)
        nonceLabel = TextView(this)
        updateNonce(intent)
        setContentView(LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            addView(nonceLabel, LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ))
            addView(editor, LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ))
        })
        editor.apply {
            hint = "Gate K host text field"
            contentDescription = "Gate K host text field"
            isFocusable = true
            isFocusableInTouchMode = true
        }
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_VISIBLE)
        editor.requestFocus()
        editor.post {
            val inputMethodManager =
                getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
            inputMethodManager?.showSoftInput(editor, InputMethodManager.SHOW_IMPLICIT)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        updateNonce(intent)
    }

    private fun updateNonce(intent: Intent) {
        val nonce = intent.getStringExtra(EXTRA_NONCE).orEmpty()
        val label = if (NONCE_PATTERN.matches(nonce)) {
            NONCE_LABEL_PREFIX + nonce
        } else {
            NONCE_LABEL_PREFIX + "unavailable"
        }
        nonceLabel.text = label
        nonceLabel.contentDescription = label
    }

    private companion object {
        const val EXTRA_NONCE = "gate_k_nonce"
        const val NONCE_LABEL_PREFIX = "Gate K screenshot nonce: "
        val NONCE_PATTERN = Regex("[A-Za-z0-9_-]{1,64}")
    }
}
