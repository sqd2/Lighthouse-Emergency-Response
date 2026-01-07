# Lighthouse Emergency Response

> A Map-Based Platform to Assist in Emergency Response Through Route Suggestion and Geographic Visibility

[![Flutter](https://img.shields.io/badge/Flutter-3.9.2-blue.svg)](https://flutter.dev/)
[![Firebase](https://img.shields.io/badge/Firebase-Latest-orange.svg)](https://firebase.google.com/)
[![Tests](https://img.shields.io/badge/Tests-56%20Passing-success.svg)]()

---

## Overview

Lighthouse is a emergency response platform designed as a final year academic project. Built with Flutter for cross-platform compatibility and Firebase for real-time capabilities.

### Key Features
- **Real-time Emergency Alerts** with GPS tracking
- **WebRTC Video/Voice Calls** for direct communication
- **End-to-End Encrypted Medical Information**
- **Two-Factor Authentication** (TOTP + Email)
- **Interactive Maps** with route navigation
- **Multi-platform**: Web (PWA), Android, iOS, Desktop

---

## Quick Start

### Prerequisites
- Flutter SDK 3.9.2 or higher
- Firebase account
- Google Maps API key
- LiveKit account (for video calls)
- Twilio account (for SMS 2FA)
- Resend account (for email 2FA)

### Installation & Running (5 minutes)

```bash
# 1. Set up client environment variables
cp .env.example .env
# Edit .env and add: GOOGLE_MAPS_API_KEY, LIVEKIT_URL

# 2. Set up server environment variables
cd functions
cp .env.example .env
# Edit functions/.env and add all API keys
cd ..

# 3. Install dependencies
flutter pub get

# 4. Configure Firebase
flutterfire configure

# 5. Run on web
flutter run -d chrome
```

**That's it!** The app will run with all features working locally. For production deployment with enhanced security, see the Firebase Secret Manager section below.

---

## Configuration

### 1. Environment Variables (Required for Testing/Evaluation)

The application uses **two separate `.env` files** for client-side and server-side configuration:

**Client-side (Root `.env`)** - Flutter app configuration:

1. Copy the example file:
```bash
cp .env.example .env
```

2. Edit `.env` with client-safe API keys:
```bash
# Google Maps API Key (domain-restricted)
GOOGLE_MAPS_API_KEY=your_google_maps_api_key_here

# LiveKit WebSocket URL (public, safe to expose)
LIVEKIT_URL=wss://your-project.livekit.cloud
```

**Server-side (`functions/.env`)** - Cloud Functions configuration:

1. Copy the example file:
```bash
cd functions
cp .env.example .env
```

2. Edit `functions/.env` with all API keys:
```bash
# Email service (Resend)
RESEND_API_KEY=your_resend_api_key_here

# SMS service (Twilio)
TWILIO_ACCOUNT_SID=your_twilio_account_sid
TWILIO_AUTH_TOKEN=your_twilio_auth_token
TWILIO_PHONE_NUMBER=+1234567890

# LiveKit (WebRTC video calls)
LIVEKIT_URL=wss://your-project.livekit.cloud
LIVEKIT_API_KEY=your_livekit_api_key_here
LIVEKIT_API_SECRET=your_livekit_api_secret_here
```

**Important:**
- Both `.env` files are git-ignored and never committed
- `.env.example` files provide templates for each environment
- **For testing/evaluation**: Fill in `functions/.env` with all keys (including LiveKit credentials)
- **For production deployment**: Migrate LiveKit credentials to Firebase Secret Manager (see section 3 below)

### 2. Firebase Setup

1. Create project at [Firebase Console](https://console.firebase.google.com/)
2. Enable services:
   - Authentication (Email/Password)
   - Firestore Database
   - Cloud Messaging
   - Firebase Storage

3. Add apps:
```bash
flutterfire configure
```

4. Configure Firestore Security Rules:
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId} {
      allow read, write: if request.auth.uid == userId;
    }
    match /emergency_alerts/{alertId} {
      allow create: if request.auth != null;
      allow read, update: if request.auth != null;
    }
  }
}
```

### 3. Firebase Secret Manager (Optional - Production Only)

**Note:** This section is OPTIONAL and only needed for production deployment. For testing/evaluation, using `functions/.env` with all keys is sufficient.

For production deployments with enhanced security, sensitive API credentials (LiveKit API Key/Secret) should be stored in Firebase Secret Manager instead of environment variables.

**Production Setup (Firebase Secrets):**

1. Set LiveKit API credentials as secrets:
```bash
# Navigate to functions directory
cd functions

# Set API Key secret
echo -n "your_livekit_api_key" | firebase functions:secrets:set LIVEKIT_API_KEY

# Set API Secret secret
echo -n "your_livekit_api_secret" | firebase functions:secrets:set LIVEKIT_API_SECRET
```

**Important:** Use `echo -n` (no trailing newline) to avoid authentication errors!

2. View configured secrets:
```bash
firebase functions:secrets:access LIVEKIT_API_KEY
firebase functions:secrets:access LIVEKIT_API_SECRET
```

3. Deploy functions with secrets:
```bash
firebase deploy --only functions
```

**Local Development Setup:**

For testing Cloud Functions locally, create a `functions/.env.local` file (git-ignored):

```bash
cd functions
cat > .env.local << EOF
# Local development secrets - DO NOT COMMIT
LIVEKIT_API_KEY=your_livekit_api_key
LIVEKIT_API_SECRET=your_livekit_api_secret
EOF
```

**How It Works:**
- Production: Cloud Functions use `defineSecret()` to access Firebase Secret Manager
- Local Dev: Functions automatically load from `.env.local` file
- Secrets are never committed to version control
- More secure than regular environment variables

### 4. Twilio Configuration (SMS for 2FA)

1. Sign up at [Twilio Console](https://www.twilio.com/console)
2. Get a phone number with SMS capabilities
3. Find your Account SID and Auth Token in the dashboard

4. Add credentials to `functions/.env`:
```bash
TWILIO_ACCOUNT_SID=your_account_sid_here
TWILIO_AUTH_TOKEN=your_auth_token_here
TWILIO_PHONE_NUMBER=+1234567890
```

**Used for:** Sending SMS verification codes during two-factor authentication

### 5. Resend Configuration (Email for 2FA)

1. Sign up at [Resend](https://resend.com/)
2. Create an API key in the dashboard
3. Verify your sending domain (or use their test domain for development)

4. Add API key to `functions/.env`:
```bash
RESEND_API_KEY=your_resend_api_key_here
```

**Used for:** Sending email verification codes during two-factor authentication

### 6. Google Maps API

1. Enable APIs in [Google Cloud Console](https://console.cloud.google.com/):
   - Maps JavaScript API
   - Maps SDK for Android/iOS
   - Places API
   - Directions API

2. Add your API key to `.env`:
```bash
GOOGLE_MAPS_API_KEY=your_actual_api_key_here
```

3. Configure API restrictions:
   - Add HTTP referrers (for web): `your-domain.com/*`
   - Restrict to necessary APIs only
   - Enable billing in Google Cloud Console

### 7. LiveKit Configuration

1. Sign up at [LiveKit Cloud](https://cloud.livekit.io/)
2. Create a new project and get your credentials

3. Add **WebSocket URL** to root `.env` (client-side):
```bash
LIVEKIT_URL=wss://your-project.livekit.cloud
```

4. Add **all LiveKit credentials** to `functions/.env` (server-side):
```bash
LIVEKIT_URL=wss://your-project.livekit.cloud
LIVEKIT_API_KEY=your_api_key_here
LIVEKIT_API_SECRET=your_api_secret_here
```

**That's it for testing/evaluation!** The app will work with video calls.

**For production deployment (optional):** Migrate API credentials to Firebase Secret Manager (see Section 3).

**Security Architecture:**
- Client app: Only knows the WebSocket URL (public, safe to expose)
- Cloud Functions: Access API Key/Secret from environment variables or Secret Manager
- Token generation happens server-side to protect credentials
- Credentials never exposed in client code or version control

---

## Running the Application

```bash
# Web (PWA)
flutter run -d chrome

# Android
flutter run -d android

# iOS (macOS only)
flutter run -d ios

# Windows Desktop
flutter run -d windows

# Build for production (Web)
flutter build web --release
```

---

## Testing

```bash
# Run all tests (56 tests)
flutter test

# Run with coverage
flutter test --coverage
```

### Test Coverage
- **Model Tests**: 26 tests (MedicalInfo, EmergencyAlert, Call)
- **Validator Tests**: 24 tests (Email, Password, Phone, Name)
- **Service Tests**: 6 tests (EncryptionService)
- **Total**: 56 tests passing

---

## Project Structure

```
lib/
├── config/              # Service configurations
├── core/                # Constants & config
├── mixins/              # Reusable behaviors
├── models/              # Data models (5 files)
├── screen/              # Full screens (11 files)
├── services/            # Business logic (12 files)
├── utils/               # Utilities & validators
├── widgets/             # Reusable UI (20 files)
└── main.dart            # Entry point
```

**Key Services:**
- `TwoFactorService`: TOTP & email 2FA
- `EncryptionService`: AES-256 medical data encryption
- `MedicalInfoService`: Encrypted medical info CRUD
- `LiveKitService`: WebRTC video/voice calls
- `NotificationService`: FCM push notifications
- `PlacesService`: Google Places API
- `DirectionsService`: Route calculation

---

## Architecture

### High-Level Overview

```
┌─────────────────┐
│  Presentation   │  Screens (11), Widgets (20)
├─────────────────┤
│ Business Logic  │  Services (12), Mixins (2)
├─────────────────┤
│   Data Layer    │  Models (5), Firebase SDK
├─────────────────┤
│    Backend      │  Firebase, LiveKit, Google APIs
└─────────────────┘
```

### Architectural Patterns
- **Service-Oriented Architecture**: Clear separation of concerns
- **Mixin-Based Code Reuse**: Shared behaviors (`LocationTrackingMixin`, `RouteNavigationMixin`)
- **Reactive Programming**: StreamBuilder with Firebase real-time listeners
- **Encryption**: AES-256-CBC for sensitive medical data

---

## Security

### Implemented Measures
1. **Authentication**
   - Firebase Auth with email/password
   - Two-Factor Authentication (TOTP + Email)
   - Session management

2. **Encryption**
   - AES-256-CBC for medical data
   - User-specific keys (SHA-256 derived from UID)
   - Encrypted before Firestore storage

3. **Access Control**
   - Role-based permissions (Citizen/Dispatcher)
   - Firestore security rules
   - Input validation

4. **Network Security**
   - HTTPS/TLS for all communications
   - WebRTC SRTP for encrypted media
   - Domain-restricted API keys

5. **Secrets Management**
   - Separate `.env` files for client and server
   - Client `.env`: Only domain-restricted/public keys (Google Maps, LiveKit URL)
   - Server `functions/.env`: All server-side API keys (Twilio, Resend, LiveKit)
   - **Testing/Evaluation**: All keys in `functions/.env` (simple setup)
   - **Production (Optional)**: Firebase Secret Manager for LiveKit credentials (enhanced security)
   - All `.env` files git-ignored and never committed to version control

---

## Deployment

### Firebase Hosting (Web PWA)

```bash
# Build
flutter build web --release

# Deploy hosting
firebase deploy --only hosting

# Access at: https://your-project.web.app
```

### Cloud Functions (Backend)

```bash
# Ensure secrets are configured (one-time setup)
cd functions
echo -n "your_livekit_api_key" | firebase functions:secrets:set LIVEKIT_API_KEY
echo -n "your_livekit_api_secret" | firebase functions:secrets:set LIVEKIT_API_SECRET

# Deploy functions
firebase deploy --only functions

# Or deploy everything at once
firebase deploy
```

**Note:** Cloud Functions automatically access secrets from Firebase Secret Manager in production.

### Android (Google Play)

```bash
# Generate keystore
keytool -genkey -v -keystore lighthouse-key.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias lighthouse

# Build
flutter build appbundle --release

# Upload to Play Console
```

### iOS (App Store)

```bash
# Open in Xcode
open ios/Runner.xcworkspace

# Archive and upload via Xcode
# Product → Archive → Distribute
```

---

## Troubleshooting

### Common Issues

**Environment variables not loading:**
```bash
# Make sure .env file exists in project root
cp .env.example .env

# Edit .env and add your keys
# Then rebuild the app
flutter clean
flutter pub get
flutter run
```

**Firebase not initialized:**
```bash
flutterfire configure
```

**Google Maps not showing:**
- Verify API key is set in `.env` file
- Enable billing in Google Cloud
- Check API restrictions
- Rebuild app after changing `.env`

**Build failed:**
```bash
flutter clean
flutter pub get
flutter run
```

**iOS pod issues:**
```bash
cd ios
pod install --repo-update
cd ..
```

---

## Features Breakdown

### Citizen Dashboard
- Emergency SOS button with service selection
- Real-time GPS tracking
- Facility search (hospitals, police, fire stations)
- Medical information management
- Video/voice calls with dispatchers
- Route navigation to facilities
- 2FA security settings

### Dispatcher Dashboard
- Live emergency alert feed
- One-click alert acceptance
- Real-time location tracking
- Medical info access (encrypted)
- Video/voice call initiation
- Analytics & statistics
- Alert history management

---

## Academic Documentation

This project demonstrates:
- **Software Engineering**: Service-oriented architecture, separation of concerns
- **Security**: End-to-end encryption, 2FA, secure authentication
- **Real-time Systems**: WebRTC, Firestore real-time sync
- **Cross-platform Development**: Flutter multi-platform support
- **Testing**: 56 unit tests with comprehensive coverage
- **Documentation**: Comprehensive code comments and README

---

## Technology Stack

**Frontend:**
- Flutter 3.9.2 (Dart)
- Material Design
- Google Maps Flutter
- LiveKit Client SDK

**Backend:**
- Firebase Authentication
- Cloud Firestore (NoSQL)
- Firebase Storage
- Firebase Cloud Messaging
- Cloud Functions (Node.js)
- LiveKit Cloud (WebRTC)

**Security:**
- `encrypt` package (AES-256)
- `pointycastle` (SHA-256)
- `otp` package (TOTP)

**External APIs:**
- Google Maps API
- Google Places API
- Google Directions API
- LiveKit API (WebRTC)
- Twilio API (SMS)
- Resend API (Email)

---

## License

Academic Project - Final Year 2025/2026

All rights reserved for academic evaluation purposes.

---

**Version:** 1.0.0
**Last Updated:** January 7, 2026
**Flutter:** 3.38.5 (minimum 3.9.2)
**Dart:** 3.10.4 (minimum 3.9.2)

