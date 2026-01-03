# Firebase Password Reset Configuration Guide

## Problem
Firebase Dynamic Links are deprecated, affecting password reset email delivery.

## Solution Steps

### 1. Firebase Console Configuration
1. Go to Firebase Console → Authentication → Templates
2. Select "Password reset" template
3. **IMPORTANT**: Update the "Action URL" to use Firebase's default hosting:
   ```
   https://YOUR_PROJECT_ID.firebaseapp.com/__/auth/action
   ```
4. Replace `YOUR_PROJECT_ID` with your actual Firebase project ID
5. Customize the email subject and body as needed
6. Save the template

### 2. Verify Authentication Settings
1. Go to Authentication → Settings
2. Ensure "Email/Password" sign-in method is enabled
3. Check that authorized domains include your app domains

### 3. Test Configuration
1. Use the forgot password feature in your app
2. Check email (including spam folder)
3. Verify the reset link works properly

## Alternative: Custom Email Handler
If you want to handle password resets within your app instead of Firebase's default page, you can:

1. Set a custom action URL in the email template
2. Add deep linking to your Flutter app
3. Handle the reset link in your app's main routing

## Common Issues & Solutions
- **Email not arriving**: Check spam folder, verify email address
- **Link not working**: Ensure Action URL is correctly configured
- **Domain issues**: Add your domain to authorized domains in Firebase Auth settings

## Code Enhancement
The current code already uses the correct Firebase method:
```dart
await FirebaseService.sendPasswordResetEmail(email);
```

No code changes are needed - this is a Firebase configuration issue.
