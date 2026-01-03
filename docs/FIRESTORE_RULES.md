Recommended Firestore security rules for a per-user profile setup

Use the following rules in the Firebase console (Firestore -> Rules) or in your project's `firestore.rules` file:

rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Allow authenticated users to read/write their own user profile
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }

    // Allow authenticated users to access their own transactions and categories
    match /transactions/{userId}/user_transactions/{docId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }

    match /categories/{userId}/user_categories/{docId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }

    // User activity (optional): only allow user to write their own activity
    match /user_activity/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }

    // By default, deny everything else
    match /{document=**} {
      allow read, write: if false;
    }
  }
}

Notes:
- These rules make sure a signed-in user can only read/write their own documents.
- If you need public read access (e.g., some categories), create a specific rule for that collection.

How to deploy:
1. In the Firebase Console go to Firestore -> Rules and paste the rules, then publish.
2. Or, if using the Firebase CLI, place the rules in `firestore.rules` and run:

   firebase deploy --only firestore:rules

If your app still gets `permission-denied` after updating rules, ensure:
- The user is actually authenticated (use `await user.getIdToken(true)` and `user.reload()` if necessary).
- You are writing documents using the UID as the document ID (the code in `FirebaseService` now does this).
- No emulator vs production mismatch (use correct project configuration and google-services files).
