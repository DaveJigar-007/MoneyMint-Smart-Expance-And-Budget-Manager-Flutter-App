const functions = require('firebase-functions');
const admin = require('firebase-admin');

// Initialize the Admin SDK
try {
    admin.initializeApp();
} catch (e) {
    // initializeApp can only be called once in some environments
}

/**
 * Trigger: onCreate of a document in `deletedUsers/{uid}`.
 * Expectation: the document ID is the user's UID in Firebase Authentication.
 * Action: attempt to delete the user from Firebase Auth using Admin SDK.
 * Result: update the document with `authDeletionStatus` and optional `authDeletionError`.
 */
exports.handleDeletedUser = functions.firestore
    .document('deletedUsers/{uid}')
    .onCreate(async (snap, context) => {
        const uid = context.params.uid;
        const ref = snap.ref;

        if (!uid) {
            await ref.update({
                authDeletionStatus: 'failed',
                authDeletionError: 'Missing UID',
                authDeletionAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            return null;
        }

        try {
            // Confirm user exists (optional)
            try {
                await admin.auth().getUser(uid);
            } catch (err) {
                // If user not found, still mark as not_found and return
                if (err.code === 'auth/user-not-found' || err.code === 'USER_NOT_FOUND') {
                    await ref.update({
                        authDeletionStatus: 'not_found',
                        authDeletionError: 'Auth user not found',
                        authDeletionAt: admin.firestore.FieldValue.serverTimestamp(),
                    });
                    return null;
                }
                // otherwise, continue to attempt delete
            }

            await admin.auth().deleteUser(uid);

            await ref.update({
                authDeletionStatus: 'success',
                authDeletionAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            return null;
        } catch (error) {
            // Write error details back to the document for debugging and retries
            await ref.update({
                authDeletionStatus: 'failed',
                authDeletionError: String(error),
                authDeletionAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            return null;
        }
    });
