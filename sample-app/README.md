# Sample App - Multilingual Demo

A simple Android app demonstrating multilingual support with English and Hindi locales.

## Features

- **Multilingual Support**: Automatically adapts UI text based on device language (English, Hindi)
- **Simple Interface**: Text input, button, and dynamic greeting display
- **Material Design**: Uses Material Components for modern UI
- **Minimal Setup**: Ready to build and test immediately

## Building the App

```bash
cd sample-app
./gradlew assembleDebug
```

The APK will be generated at:
```
app/build/outputs/apk/debug/app-debug.apk
```

## Supported Languages

| Language | Code | Strings File |
|----------|------|--------------|
| English (default) | `en` | `values/strings.xml` |
| Hindi | `hi` | `values-hi/strings.xml` |

## Testing with Firebase Test Lab

This app is designed to work with the FTL scripts in `../ftl-scripts/`.

### Test in Multiple Languages

```bash
cd ../ftl-scripts

# Test in English and Hindi
./run-ftl-multilang.sh \
  --service-account-key ~/gcp-key.json \
  --phone 9876543210 \
  --otp 123456 \
  --locales en,hi
```

Screenshots will be organized by language:
```
screenshots/
├── en/
│   ├── device1/
│   └── device2/
└── hi/
    ├── device1/
    └── device2/
```

## App Structure

```
sample-app/
├── app/
│   ├── src/main/
│   │   ├── java/com/example/sampleapp/
│   │   │   └── MainActivity.kt          # Main activity
│   │   ├── res/
│   │   │   ├── layout/
│   │   │   │   └── activity_main.xml    # UI layout
│   │   │   ├── values/
│   │   │   │   ├── strings.xml          # English strings
│   │   │   │   ├── colors.xml           # Color palette
│   │   │   │   └── themes.xml           # App theme
│   │   │   └── values-hi/
│   │   │       └── strings.xml          # Hindi strings
│   │   └── AndroidManifest.xml
│   └── build.gradle
├── build.gradle
├── settings.gradle
└── gradle.properties
```

## UI Components

1. **Welcome Text**: Displays app name (localized)
2. **Description**: App description (localized)
3. **Name Input**: Text field for user's name
4. **Submit Button**: Triggers greeting display (localized)
5. **Greeting Text**: Personalized greeting (localized)
6. **Features List**: Key features (localized)

## Adding More Languages

To add support for a new language:

1. Create a new values folder: `app/src/main/res/values-<language_code>/`
2. Copy `strings.xml` to the new folder
3. Translate all string values (keep the keys unchanged)

Example for Spanish:
```bash
mkdir -p app/src/main/res/values-es/
cp app/src/main/res/values/strings.xml app/src/main/res/values-es/
# Edit values-es/strings.xml with Spanish translations
```

## Requirements

- **Java**: JDK 17 or higher
- **Gradle**: 8.2 (included via wrapper)
- **Android SDK**: API 35 (compileSdk)
- **Min Android Version**: API 24 (Android 7.0)

## License

This is a sample/demo app for testing purposes.
