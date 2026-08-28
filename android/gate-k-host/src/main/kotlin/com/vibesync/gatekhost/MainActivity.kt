package com.vibesync.gatekhost

import android.app.Activity
import android.content.Context
import android.os.Bundle
import android.view.WindowManager
import android.view.inputmethod.InputMethodManager
import android.widget.EditText

/** Disposable foreground text host used only to make the IME surface visible. */
class MainActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val editor = EditText(this).apply {
            hint = "Gate K host text field"
            contentDescription = "Gate K host text field"
            isFocusable = true
            isFocusableInTouchMode = true
        }
        setContentView(editor)
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_VISIBLE)
        editor.requestFocus()
        editor.post {
            val inputMethodManager =
                getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
            inputMethodManager?.showSoftInput(editor, InputMethodManager.SHOW_IMPLICIT)
        }
    }
}
