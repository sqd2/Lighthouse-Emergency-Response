# Lighthouse Emergency App - Refactoring Guide

## Overview

This document outlines the systematic refactoring of the Lighthouse Emergency application to follow industry best practices for code organization, modularity, and maintainability.

## Refactoring Objectives

1. Improve code organization and file structure
2. Reduce file sizes to manageable chunks (200-400 lines max)
3. Centralize configuration and API key management
4. Establish clear separation of concerns
5. Enhance code readability with professional documentation
6. Facilitate easier testing and maintenance

## Completed Phases

### Phase 1: File Organization (✓ COMPLETED)

**Actions Taken:**
- Moved `lib/directions_service.dart` → `lib/services/directions_service.dart`
- Moved `lib/places_service.dart` → `lib/services/places_service.dart`
- Updated all import statements across the codebase
- Removed empty directories: `lib/presentation`, `lib/shared`, `lib/user`
- Created core directory structure: `lib/core/config`, `lib/core/constants`

**Impact:** Better adherence to Flutter project structure conventions

### Phase 2: API Configuration Management (✓ COMPLETED)

**Actions Taken:**
- Created `lib/core/config/api_config.dart` for centralized API key management
- Created `lib/core/constants/app_constants.dart` for application-wide constants
- Updated `DirectionsService` and `PlacesService` to use centralized configuration
- Added professional documentation with first-person perspective
- Implemented configuration validation methods

**Impact:**
- Single source of truth for API configuration
- Easier environment-based configuration management
- Improved security through proper key management patterns

**Files Modified:**
- `lib/services/directions_service.dart`
- `lib/services/places_service.dart`

## Pending Phases

### Phase 3: Cloud Functions Modularization (🔄 IN PROGRESS)

**Current State:**
- `functions/index.js`: 1,385 lines (CRITICAL - TOO LARGE)
- All functions in single file
- Helper functions mixed with exports
- Difficult to maintain and test

**Target Structure:**
```
functions/
├── index.js (exports only, ~50 lines)
├── package.json
├── .env
├── .gitignore
└── src/
    ├── config/
    │   └── firebase-config.js (Firebase admin initialization)
    ├── helpers/
    │   ├── emergency-contact.js (getEmergencyContact, notifyEmergencyContact)
    │   ├── user-helpers.js (getUserName, getUserRole, etc.)
    │   ├── notification-helpers.js (sendNotification, sendToDevices)
    │   └── distance-helpers.js (calculateDistance, isWithinRange)
    ├── triggers/
    │   ├── sos-triggers.js (onSOSCreated, onSOSAccepted, onSOSCancelled, onSOSResolved)
    │   ├── dispatcher-triggers.js (onDispatcherArrived)
    │   ├── message-triggers.js (onMessageSent)
    │   └── call-triggers.js (onCallCreated)
    └── api/
        ├── places.js (searchNearbyPlaces)
        ├── directions.js (getDirections)
        ├── notifications.js (testNotification, sendEmergencyContactSMS)
        ├── livekit.js (generateLiveKitToken)
        ├── email.js (sendEmail)
        ├── sms.js (sendSMS)
        └── facilities.js (deleteAllFacilities)
```

**Refactoring Steps:**

1. **Extract Helper Functions** (~2 hours)
   ```javascript
   // functions/src/helpers/emergency-contact.js
   const admin = require('firebase-admin');
   const {twilioAccountSid, twilioAuthToken, twilioPhoneNumber, resendApiKey} = require('../config/secrets');

   /**
    * Retrieves emergency contact information from user's encrypted medical records.
    *
    * This function queries the user's medical information, decrypts it using a key
    * derived from the user's UID, and extracts the emergency contact details.
    *
    * @param {string} userId - The Firebase Auth UID of the user
    * @returns {Promise<Object|null>} Emergency contact object or null if not found
    */
   async function getEmergencyContact(userId) {
     // Implementation...
   }

   /**
    * Sends notification to the user's emergency contact via SMS or email.
    *
    * I attempt to send via SMS first (preferred method), falling back to email
    * if SMS fails or if no phone number is available.
    *
    * @param {string} userId - The Firebase Auth UID of the user
    * @param {string} userName - Display name of the user
    * @param {string} userEmail - Email address of the user
    * @param {string} message - Message body to send
    * @param {string} subject - Email subject line
    * @returns {Promise<void>}
    */
   async function notifyEmergencyContact(userId, userName, userEmail, message, subject) {
     // Implementation...
   }

   module.exports = {getEmergencyContact, notifyEmergencyContact};
   ```

2. **Extract SOS Triggers** (~3 hours)
   ```javascript
   // functions/src/triggers/sos-triggers.js
   const {onDocumentCreated, onDocumentUpdated} = require('firebase-functions/v2/firestore');
   const {getEmergencyContact, notifyEmergencyContact} = require('../helpers/emergency-contact');
   const {getUserName} = require('../helpers/user-helpers');
   const {sendNotificationToDispatchers} = require('../helpers/notification-helpers');

   /**
    * Triggered when a new SOS emergency alert is created.
    *
    * This function performs the following actions:
    * 1. Retrieves the citizen's information
    * 2. Identifies nearby dispatchers
    * 3. Sends push notifications to all active dispatchers
    * 4. Notifies the citizen's emergency contact
    */
   exports.onSOSCreated = onDocumentCreated(
     {
       document: "emergency_alerts/{alertId}",
       region: "us-central1",
     },
     async (event) => {
       // Implementation...
     }
   );

   // ... other SOS triggers
   ```

3. **Extract API Functions** (~2 hours)
   ```javascript
   // functions/src/api/places.js
   const {onRequest} = require('firebase-functions/v2/https');
   const {defineSecret} = require('firebase-functions/params');

   const googleMapsApiKey = defineSecret('GOOGLE_MAPS_API_KEY');

   /**
    * HTTP endpoint for searching nearby emergency facilities.
    *
    * This Cloud Function acts as a proxy to Google Places API, avoiding CORS
    * issues when called from web clients. I implement caching at the client
    * level to minimize API calls.
    *
    * @param {Object} request - Express request object
    * @param {Object} response - Express response object
    */
   exports.searchNearbyPlaces = onRequest(
     {cors: true, secrets: [googleMapsApiKey]},
     async (request, response) => {
       // Implementation...
     }
   );
   ```

4. **Update index.js** (~30 minutes)
   ```javascript
   // functions/index.js
   /**
    * Firebase Cloud Functions for Lighthouse Emergency Application
    *
    * This file serves as the main entry point, importing and exporting all
    * Cloud Functions organized by category. The actual implementations are
    * in modular files within the src/ directory.
    */

   // SOS Alert Triggers
   const {onSOSCreated, onSOSAccepted, onSOSCancelled, onSOSResolved} = require('./src/triggers/sos-triggers');
   const {onDispatcherArrived} = require('./src/triggers/dispatcher-triggers');

   // Communication Triggers
   const {onMessageSent} = require('./src/triggers/message-triggers');
   const {onCallCreated} = require('./src/triggers/call-triggers');

   // API Endpoints
   const {searchNearbyPlaces} = require('./src/api/places');
   const {getDirections} = require('./src/api/directions');
   const {testNotification, sendEmergencyContactSMS} = require('./src/api/notifications');
   const {generateLiveKitToken} = require('./src/api/livekit');
   const {sendEmail} = require('./src/api/email');
   const {sendSMS} = require('./src/api/sms');
   const {deleteAllFacilities} = require('./src/api/facilities');

   // Export all functions
   module.exports = {
     // Triggers
     onSOSCreated,
     onSOSAccepted,
     onSOSCancelled,
     onSOSResolved,
     onDispatcherArrived,
     onMessageSent,
     onCallCreated,

     // API
     searchNearbyPlaces,
     getDirections,
     testNotification,
     sendEmergencyContactSMS,
     generateLiveKitToken,
     sendEmail,
     sendSMS,
     deleteAllFacilities,
   };
   ```

**Benefits:**
- Each file < 300 lines
- Clear responsibility separation
- Easier to test individual functions
- Better code navigation
- Simpler code reviews

### Phase 4: Flutter Widget Splitting (PENDING)

**Target Files:**
1. `lib/screen/dispatcher_dashboard.dart` (1,167 lines → 3-4 files)
2. `lib/widgets/chat_screen.dart` (1,012 lines → 4-5 files)
3. `lib/widgets/sos_widgets.dart` (979 lines → 3 files)
4. `lib/screen/citizen_dashboard.dart` (907 lines → 3-4 files)
5. `lib/widgets/map_view.dart` (877 lines → 3-4 files)
6. `lib/widgets/emergency_alert_widget.dart` (867 lines → 2-3 files)

**Example: Splitting sos_widgets.dart**

Current structure (979 lines):
```dart
// lib/widgets/sos_widgets.dart
class SOSSheet extends StatefulWidget { ... }
class ActiveSOSBanner extends StatefulWidget { ... }
class UpdateSOSSheet extends StatefulWidget { ... }
```

Target structure:
```dart
// lib/widgets/sos/sos_sheet.dart
class SOSSheet extends StatefulWidget { ... }

// lib/widgets/sos/active_sos_banner.dart
class ActiveSOSBanner extends StatefulWidget { ... }

// lib/widgets/sos/update_sos_sheet.dart
class UpdateSOSSheet extends StatefulWidget { ... }

// lib/widgets/sos/sos_widgets.dart (barrel file)
export 'sos_sheet.dart';
export 'active_sos_banner.dart';
export 'update_sos_sheet.dart';
```

**Steps:**
1. Create widget subdirectories (`lib/widgets/sos/`, `lib/widgets/chat/`, etc.)
2. Extract individual widgets into separate files
3. Create barrel export files for clean imports
4. Update all imports across the codebase
5. Test to ensure no broken references

**Estimated Time:** 6-8 hours

### Phase 5: Comment Standardization (PENDING)

**Current Issues:**
- Inconsistent comment styles
- Some comments use emojis
- Mix of casual and professional tone
- Missing documentation in some areas

**Standards to Apply:**

1. **File-Level Documentation:**
   ```dart
   /// Service responsible for managing encrypted medical information.
   ///
   /// This service handles CRUD operations for user medical data, implementing
   /// client-side encryption using AES-256-CBC. I ensure that sensitive medical
   /// information is encrypted before storage and decrypted only when needed.
   ///
   /// Medical data includes:
   /// - Blood type
   /// - Allergies and medications
   /// - Pre-existing medical conditions
   /// - Emergency contact information
   ```

2. **Method Documentation:**
   ```dart
   /// Saves medical information with client-side encryption.
   ///
   /// I encrypt the medical data using an encryption key derived from the user's
   /// Firebase UID before storing it in Firestore. This ensures that medical
   /// information remains confidential even if the database is compromised.
   ///
   /// The emergency contact phone number is stored separately (unencrypted) to
   /// enable Cloud Functions to send SMS notifications without requiring
   /// decryption capabilities.
   ///
   /// @param medicalInfo The medical information to encrypt and store
   /// @throws Exception if user is not authenticated
   /// @throws Exception if encryption or storage fails
   ```

3. **Inline Comments:**
   ```dart
   // Check for existing pending or active SOS before allowing new submission.
   // This validation prevents users from creating multiple simultaneous alerts,
   // which could confuse dispatchers and waste emergency response resources.
   final existingAlerts = await FirebaseFirestore.instance
       .collection('emergency_alerts')
       .where('userId', isEqualTo: user.uid)
       .where('status', whereIn: ['pending', 'active'])
       .limit(1)
       .get();
   ```

4. **Remove All Emojis:**
   - Replace `` with professional comments
   - Replace `` with "Successfully completed"
   - Replace `` with "Error occurred"

**Estimated Time:** 3-4 hours

### Phase 6: Testing & Deployment (PENDING)

**Test Plan:**

1. **Unit Tests** (if not already present)
   - Test individual services
   - Test helper functions
   - Test model serialization/deserialization

2. **Integration Tests**
   - Test SOS creation flow
   - Test dispatcher acceptance flow
   - Test emergency contact notifications
   - Test location tracking and routing

3. **Manual Testing Checklist**
   - [ ] Create SOS as citizen
   - [ ] Accept SOS as dispatcher
   - [ ] Send chat messages
   - [ ] Mark as arrived
   - [ ] Resolve SOS
   - [ ] Cancel SOS
   - [ ] Verify emergency contact receives notifications
   - [ ] Test with multiple dispatchers
   - [ ] Test offline/online transitions
   - [ ] Test on web and mobile platforms

4. **Deployment Steps**
   - Run `flutter analyze` to check for issues
   - Run existing tests
   - Build web version: `flutter build web`
   - Deploy Cloud Functions: `firebase deploy --only functions`
   - Deploy hosting: `firebase deploy --only hosting`
   - Monitor Firebase logs for errors
   - Verify all functions are working in production

**Estimated Time:** 4-6 hours

## Best Practices Implemented

### Code Organization
- ✅ Services in `lib/services/`
- ✅ Models in `lib/models/`
- ✅ Widgets in `lib/widgets/`
- ✅ Screens in `lib/screen/`
- ✅ Configuration in `lib/core/config/`
- ✅ Constants in `lib/core/constants/`
- ✅ Utilities in `lib/utils/`
- ✅ Mixins in `lib/mixins/`

### API Key Management
- ✅ Centralized in `api_config.dart`
- ✅ Support for environment variables
- ✅ Default values for development
- ✅ Validation methods
- ✅ Professional documentation

### Documentation Standards
- ✅ First-person perspective ("I implement...", "I ensure...")
- ✅ No emojis in code or comments
- ✅ Clear method descriptions
- ✅ Parameter documentation
- ✅ Return value documentation
- ✅ Exception documentation

### Security
- ✅ Secrets in environment variables
- ✅ `.env` files in `.gitignore`
- ✅ API keys with domain restrictions
- ✅ Client-side encryption for sensitive data

## Next Steps

1. **Complete Phase 3:** Modularize Cloud Functions
   - Extract helper functions
   - Split triggers into separate files
   - Organize API endpoints
   - Update index.js to import/export

2. **Complete Phase 4:** Split large Flutter files
   - Prioritize files > 800 lines
   - Create feature-based widget directories
   - Implement barrel exports

3. **Complete Phase 5:** Standardize all comments
   - Remove emojis
   - Apply professional tone
   - Add missing documentation

4. **Complete Phase 6:** Test and deploy
   - Run comprehensive tests
   - Deploy to production
   - Monitor for issues

## Rollback Plan

If issues arise after refactoring:

1. **Git History:** All changes are committed incrementally
2. **Revert Command:** `git revert <commit-hash>`
3. **Redeploy:** `firebase deploy` to restore previous version
4. **Testing:** Always test in development before production deployment

## References

- [Flutter Style Guide](https://dart.dev/guides/language/effective-dart/style)
- [Firebase Best Practices](https://firebase.google.com/docs/functions/best-practices)
- [Clean Code Principles](https://www.amazon.com/Clean-Code-Handbook-Software-Craftsmanship/dp/0132350882)
- [Effective Dart Documentation](https://dart.dev/guides/language/effective-dart/documentation)

## Maintenance

This refactoring guide should be updated as:
- New phases are completed
- New best practices are discovered
- Architecture decisions are made
- Issues are encountered and resolved

Last Updated: 2025-12-28
Status: Phases 1-2 Complete, Phase 3 In Progress
