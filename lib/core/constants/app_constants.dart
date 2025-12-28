/// Application-wide constants and configuration values.
///
/// This file centralizes all constant values used throughout the application,
/// including Firebase collection names, storage paths, and application settings.
class AppConstants {
  /// Private constructor to prevent instantiation of this utility class.
  AppConstants._();

  // Firestore Collection Names
  /// Firestore collection for storing user profile data.
  static const String usersCollection = 'users';

  /// Firestore collection for emergency alerts/SOS incidents.
  static const String emergencyAlertsCollection = 'emergency_alerts';

  /// Firestore collection for emergency facilities (hospitals, police, etc.).
  static const String emergencyFacilitiesCollection = 'emergency_facilities';

  /// Firestore collection for chat messages within emergency alerts.
  static const String messagesSubcollection = 'messages';

  /// Firestore collection for medical information (encrypted).
  static const String medicalInfoSubcollection = 'medical_info';

  /// Firestore collection for device tokens used for push notifications.
  static const String deviceTokensSubcollection = 'deviceTokens';

  // User Roles
  /// User role identifier for citizens who can create emergency alerts.
  static const String roleCitizen = 'citizen';

  /// User role identifier for dispatchers who respond to emergency alerts.
  static const String roleDispatcher = 'dispatcher';

  // Emergency Alert Status
  /// Alert status when first created, awaiting dispatcher acceptance.
  static const String statusPending = 'pending';

  /// Alert status when a dispatcher has accepted and is en route.
  static const String statusActive = 'active';

  /// Alert status when dispatcher has arrived at the emergency location.
  static const String statusArrived = 'arrived';

  /// Alert status when the emergency has been resolved successfully.
  static const String statusResolved = 'resolved';

  /// Alert status when the citizen has cancelled the alert.
  static const String statusCancelled = 'cancelled';

  // Emergency Service Types
  /// Service type identifier for hospital/medical emergencies.
  static const String serviceHospital = 'Hospital';

  /// Service type identifier for police assistance.
  static const String servicePolice = 'Police Station';

  /// Service type identifier for fire department assistance.
  static const String serviceFire = 'Fire Station';

  /// Service type identifier for ambulance services.
  static const String serviceAmbulance = 'Ambulance';

  // Location & Map Settings
  /// Default map zoom level for displaying user location.
  static const double defaultMapZoom = 15.0;

  /// Minimum distance (meters) user must move before location update.
  static const double locationUpdateThreshold = 10.0;

  /// Radius (meters) for searching nearby emergency facilities.
  static const int facilitiesSearchRadius = 5000;

  /// Maximum distance (meters) for dispatcher to accept an alert.
  static const double maxDispatcherDistance = 50000.0;

  // Cache & Performance
  /// Duration for caching API responses to reduce external API calls.
  static const Duration apiCacheDuration = Duration(minutes: 10);

  /// Maximum number of items to cache in memory.
  static const int maxCacheSize = 100;

  // Notification Settings
  /// Topic name for FCM notifications to all dispatchers.
  static const String dispatcherNotificationTopic = 'dispatchers';

  /// Channel ID for emergency alert notifications on Android.
  static const String emergencyNotificationChannel = 'emergency_alerts';

  // Time Limits
  /// Maximum time (minutes) before an unaccepted alert expires.
  static const int alertExpirationMinutes = 30;

  /// Timeout duration for network requests.
  static const Duration networkTimeout = Duration(seconds: 30);

  // File Storage
  /// Firebase Storage path for user profile images.
  static const String profileImagesPath = 'profile_images';

  /// Firebase Storage path for facility images.
  static const String facilityImagesPath = 'facility_images';

  /// Maximum file size (bytes) for profile image uploads.
  static const int maxProfileImageSize = 5 * 1024 * 1024; // 5 MB

  // Validation
  /// Minimum password length for user accounts.
  static const int minPasswordLength = 8;

  /// Regular expression pattern for validating phone numbers.
  static const String phoneRegexPattern = r'^\+?[1-9]\d{1,14}$';

  /// Regular expression pattern for validating email addresses.
  static const String emailRegexPattern = r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$';

  // UI Configuration
  /// Default padding value for consistent spacing.
  static const double defaultPadding = 16.0;

  /// Default border radius for rounded corners.
  static const double defaultBorderRadius = 12.0;

  /// Animation duration for transitions and state changes.
  static const Duration animationDuration = Duration(milliseconds: 300);
}
