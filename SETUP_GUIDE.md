# MoneyMint - Setup Guide

This guide provides step-by-step instructions to set up the MoneyMint application on a new development machine.

## Prerequisites

### 1. Install Flutter SDK
1. Download the latest stable Flutter SDK from [flutter.dev](https://flutter.dev/docs/get-started/install)
2. Extract the downloaded zip file to a location of your choice (e.g., `C:\src\flutter`)
3. Add Flutter to your system PATH:
   - Windows: Add `C:\src\flutter\bin` to your system PATH
   - macOS/Linux: Add `export PATH="$PATH:`pwd`/flutter/bin"` to your `~/.bashrc` or `~/.zshrc`
4. Verify installation by running:
   ```bash
   flutter doctor
   ```

### 2. Install Android Studio (for Android development)
1. Download and install [Android Studio](https://developer.android.com/studio)
2. During installation, make sure to install:
   - Android SDK
   - Android SDK Command-line Tools
   - Android SDK Build-Tools
   - Android Emulator (optional)
3. Accept Android licenses:
   ```bash
   flutter doctor --android-licenses
   ```

### 3. Install Xcode (for iOS development - macOS only)
1. Install Xcode from the Mac App Store
2. Install Xcode command line tools:
   ```bash
   xcode-select --install
   ```
3. Set up the iOS simulator:
   ```bash
   sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
   sudo xcodebuild -runFirstLaunch
   ```

### 4. Install Node.js and npm
1. Download and install Node.js (LTS version) from [nodejs.org](https://nodejs.org/)
2. Verify installation:
   ```bash
   node --version
   npm --version
   ```

## Project Setup

### 1. Clone the Repository
```bash
git clone <repository-url>
cd MoneyMint
```

### 2. Install Flutter Dependencies
```bash
flutter pub get
```

### 3. Set Up Firebase
1. Install Firebase CLI:
   ```bash
   npm install -g firebase-tools
   ```
2. Log in to Firebase:
   ```bash
   firebase login
   ```
3. Set up Firebase project (if not already done):
   ```bash
   firebase init
   ```

### 4. Configure Firebase for Your Platform

#### Android
1. Get the `google-services.json` file from Firebase Console
2. Place it in: `android/app/google-services.json`

#### iOS (macOS only)
1. Get the `GoogleService-Info.plist` from Firebase Console
2. Place it in: `ios/Runner/GoogleService-Info.plist`
3. Run:
   ```bash
   cd ios
   pod install
   cd ..
   ```

#### Web
1. Get the Firebase configuration from Firebase Console
2. Update the web configuration in `web/index.html`

### 5. Install Firebase Functions Dependencies
```bash
cd functions
npm install
cd ..
```

## Running the App

### For Android
```bash
flutter run -d <device_id>
# or
flutter build apk
```

### For iOS (macOS only)
```bash
flutter run -d <device_id>
# or open in Xcode
open ios/Runner.xcworkspace
```

### For Web
```bash
flutter run -d chrome
```

## Firebase Emulator (Optional)
To run with Firebase emulators:
```bash
cd functions
npm run serve
# In another terminal
flutter run -d <device_id> --dart-define=USE_FIREBASE_EMULATOR=true
```

## Troubleshooting

### Common Issues
1. **Android SDK not found**:
   - Set `ANDROID_HOME` to your Android SDK location
   - Run `flutter doctor --android-licenses`

2. **CocoaPods not installed** (macOS):
   ```bash
   sudo gem install cocoapods
   ```

3. **Firebase configuration errors**:
   - Verify all configuration files are in the correct locations
   - Make sure package names match in Firebase Console and your app

## Support
For additional help, please contact the development team or refer to the project documentation.
