package com.example.sampleapp

import android.os.Bundle
import android.widget.Button
import android.widget.EditText
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {

    private lateinit var welcomeText: TextView
    private lateinit var nameInput: EditText
    private lateinit var submitButton: Button
    private lateinit var greetingText: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        welcomeText = findViewById(R.id.welcomeText)
        nameInput = findViewById(R.id.nameInput)
        submitButton = findViewById(R.id.submitButton)
        greetingText = findViewById(R.id.greetingText)

        submitButton.setOnClickListener {
            val name = nameInput.text.toString()
            if (name.isNotEmpty()) {
                greetingText.text = getString(R.string.greeting_message, name)
            } else {
                greetingText.text = getString(R.string.please_enter_name)
            }
        }
    }
}
