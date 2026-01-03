import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FirebaseService {
  // Singleton instance
  static final FirebaseService _instance = FirebaseService._internal();
  factory FirebaseService() => _instance;
  FirebaseService._internal();

  // Firebase instances
  static late final FirebaseAuth _auth;
  static late final FirebaseFirestore _firestore;

  // Collections
  static const String transactionsCollection = 'transactions';
  static const String usersCollection = 'users';
  static const String categoriesCollection = 'categories';
  
  // Getters
  static FirebaseAuth get auth => _auth;
  static FirebaseFirestore get firestore => _firestore;
  
  // Auth Methods
  static Future<UserCredential> signInWithEmailAndPassword(
      String email, String password) async {
    try {
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      // Check if user is blocked
      final userDoc = await _firestore
          .collection(usersCollection)
          .doc(userCredential.user!.uid)
          .get();
          
      if (userDoc.exists && userDoc.data()?['isBlocked'] == true) {
        await _auth.signOut();
        throw FirebaseAuthException(
          code: 'user-blocked',
          message: 'This account has been blocked by the administrator.',
        );
      }
      
      // Update user's last active timestamp on successful login
      await _updateUserActivity();
      
      return userCredential;
    } catch (e) {
      rethrow;
    }
  }
  
  static Future<void> signOut() async {
    await _auth.signOut();
  }
  
  // Check if current user is blocked
  static Future<bool> isCurrentUserBlocked() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    
    final userDoc = await _firestore
        .collection(usersCollection)
        .doc(user.uid)
        .get();
        
    return userDoc.exists && userDoc.data()?['isBlocked'] == true;
  }
  
  // Transaction Methods
  static Future<void> addTransaction(Map<String, dynamic> transactionData) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('User not authenticated');
      
      await _firestore
          .collection(transactionsCollection)
          .doc(user.uid)
          .collection('user_transactions')
          .add({
            ...transactionData,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      throw Exception('Failed to add transaction: $e');
    }
  }
  
  // Category Methods
  static Future<String> addCategory(Map<String, dynamic> categoryData) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('User not authenticated');
      
      final docRef = await _firestore
          .collection(categoriesCollection)
          .doc(user.uid)
          .collection('user_categories')
          .add({
            ...categoryData,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          
      return docRef.id;
    } catch (e) {
      throw Exception('Failed to add category: $e');
    }
  }
  
  static Stream<QuerySnapshot> getCategoriesStream({String? type}) {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');
    
    var query = _firestore
        .collection(categoriesCollection)
        .doc(user.uid)
        .collection('user_categories');
        
    Query filteredQuery = query;
    if (type != null) {
      filteredQuery = query.where('type', isEqualTo: type);
    }
    
    return filteredQuery.orderBy('name').snapshots();
  }
  
  static Future<void> deleteCategory(String categoryId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('User not authenticated');
      
      await _firestore
          .collection(categoriesCollection)
          .doc(user.uid)
          .collection('user_categories')
          .doc(categoryId)
          .delete();
    } catch (e) {
      throw Exception('Failed to delete category: $e');
    }
  }

  static Stream<QuerySnapshot> getTransactionsStream() {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');
    
    return _firestore
        .collection(transactionsCollection)
        .doc(user.uid)
        .collection('user_transactions')
        .orderBy('date', descending: true)
        .snapshots();
  }

  // Initialize Firebase
  static Future<void> initialize() async {
    await Firebase.initializeApp();
    _auth = FirebaseAuth.instance;
    _firestore = FirebaseFirestore.instance;
    
    // Update user's last active timestamp when initializing the app
    _updateUserActivity();
  }
  
  // Update user's last active timestamp
  static Future<void> _updateUserActivity() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        await _firestore.collection('user_activity').doc(user.uid).set({
          'lastActive': FieldValue.serverTimestamp(),
          'userId': user.uid,
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('Error updating user activity: $e');
    }
  }

  // Email & Password Authentication

  static Future<UserCredential> createUserWithEmailAndPassword(
      String email, String password, String name, {File? profileImage}) async {
    try {
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Use default profile image from assets
      String photoURL = 'assets/usersPic/default_profile.png';
      
      // If a custom image is provided, use it (assuming it's already in the assets)
      if (profileImage != null) {
        try {
          final fileName = profileImage.path.split('/').last;
          photoURL = 'assets/usersPic/$fileName';
        } catch (e) {
          debugPrint('Error setting profile image: $e');
        }
      }

      // Update user display name and photo URL
      await userCredential.user?.updateDisplayName(name);
      await userCredential.user?.updatePhotoURL(photoURL);
          
      // Save additional user data to Firestore
      await _firestore
          .collection('users')
          .doc(userCredential.user?.uid)
          .set({
            'name': name,
            'email': email,
            'photoURL': photoURL,
            'role': 'user',
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });

      return userCredential;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  // User sign out
  static Future<void> userSignOut() async {
    await _auth.signOut();
  }

  static Future<void> updateProfileImage(File imageFile) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('No user is currently signed in');
      
      // Generate a unique file name with timestamp and user ID
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileExtension = imageFile.path.split('.').last.toLowerCase();
      final fileName = 'profile_${user.uid}_$timestamp.$fileExtension';
      
      // Define the target directory and file
      final Directory targetDir = Directory('${Directory.current.path}/assets/usersPic');
      final File targetFile = File('${targetDir.path}/$fileName');
      
      // Ensure the target directory exists
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }
      
      // Copy the file to the assets directory
      await imageFile.copy(targetFile.path);
      
      // The path to use in the app (relative to assets folder)
      final assetPath = 'assets/usersPic/$fileName';
      
      // Update user's photoURL in Firebase Auth
      await user.updatePhotoURL(assetPath);
      
      // Update in Firestore
      await _firestore.collection('users').doc(user.uid).update({
        'photoURL': assetPath,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      debugPrint('Profile image updated successfully: $assetPath');
    } catch (e) {
      debugPrint('Error updating profile image: $e');
      rethrow;
    }
  }

  // Get local asset path for profile image
  static Future<String> getLocalImagePath(File imageFile, String fileName) async {
    try {
      // Ensure the file exists
      if (!await imageFile.exists()) {
        debugPrint('Image file does not exist: ${imageFile.path}');
        return 'assets/usersPic/default_profile.png';
      }
      
      // Generate a unique file name
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileExtension = imageFile.path.split('.').last.toLowerCase();
      final uniqueFileName = 'img_${timestamp}_${fileName.hashCode}.$fileExtension';
      
      // Define the target directory and file
      final Directory targetDir = Directory('${Directory.current.path}/assets/usersPic');
      final File targetFile = File('${targetDir.path}/$uniqueFileName');
      
      // Ensure the target directory exists
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }
      
      // Copy the file if it doesn't exist
      if (!await targetFile.exists()) {
        await imageFile.copy(targetFile.path);
      }
      
      // Return the path relative to the assets folder
      return 'assets/usersPic/$uniqueFileName';
    } catch (e) {
      debugPrint('Error getting local image path: $e');
      // Return default profile image path in case of error
      return 'assets/usersPic/default_profile.png';
    }
  }

  // Password Reset
  static Future<void> sendPasswordResetEmail(String email) async {
    try {
      final actionCodeSettings = ActionCodeSettings(
        url: 'https://money--mint.firebaseapp.com/__/auth/action',
        handleCodeInApp: false,
        iOSBundleId: 'com.example.money_mint',
        androidPackageName: 'com.example.money_mint',
        androidInstallApp: true,
        androidMinimumVersion: '1',
      );
      
      await _auth.sendPasswordResetEmail(
        email: email,
        actionCodeSettings: actionCodeSettings,
      );
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  // Error handling
  static String _handleAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No user found with this email.';
      case 'wrong-password':
        return 'Incorrect password.';
      case 'email-already-in-use':
        return 'This email is already in use.';
      case 'weak-password':
        return 'The password is too weak.';
      case 'invalid-email':
        return 'The email address is not valid.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many login attempts. Please try again later.';
      case 'operation-not-allowed':
        return 'This operation is not allowed. Please contact support.';
      default:
        return 'An error occurred. Please try again.';
    }
  }

  // Check if user is signed in
  static bool get isSignedIn => _auth.currentUser != null;

  // Get current user
  static User? get currentUser => _auth.currentUser;

  // Auth state changes stream
  static Stream<User?> get authStateChanges => _auth.authStateChanges();

 

  // Get all transactions for the current user
  static Stream<QuerySnapshot> getTransactions() {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    return _firestore
        .collection('transactions')
        .where('userId', isEqualTo: user.uid)
        .orderBy('date', descending: true)
        .snapshots();
  }

  // Get all expense categories
  static Stream<QuerySnapshot> getExpenseCategories() {
    return _firestore
        .collection('categories')
        .where('type', isEqualTo: 'expense')
        .orderBy('name')
        .snapshots();
  }

}
