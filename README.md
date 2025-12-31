# 🚨 Lighthouse Emergency Response System

> A cross-platform emergency response system connecting citizens with dispatchers in real-time.

[![Flutter](https://img.shields.io/badge/Flutter-3.9.2-blue.svg)](https://flutter.dev/)
[![Firebase](https://img.shields.io/badge/Firebase-Latest-orange.svg)](https://firebase.google.com/)
[![Tests](https://img.shields.io/badge/Tests-42%20Passing-success.svg)]()

---

## 📋 Overview

Lighthouse is a comprehensive emergency response platform designed for final year academic project evaluation. Built with Flutter for cross-platform compatibility and Firebase for real-time capabilities.

### Key Features
- 🆘 **Real-time Emergency Alerts** with GPS tracking
- 📞 **WebRTC Video/Voice Calls** for direct communication
- 💊 **End-to-End Encrypted Medical Information**
- 🔒 **Two-Factor Authentication** (TOTP + Email)
- 🗺️ **Interactive Maps** with route navigation
- 📱 **Multi-platform**: Web (PWA), Android, iOS, Desktop

---

## 🚀 Quick Start

### Prerequisites
- Flutter SDK 3.9.2 or higher
- Firebase account
- Google Maps API key
- LiveKit account (for video calls)
- Twilio account (for SMS 2FA)
- Resend account (for email 2FA)

### Installation

```bash
# Clone repository
git clone https://github.com/yourusername/lighthouse.git
cd lighthouse

# Set up environment variables
cp .env.example .env
# Edit .env file and add your API keys

# Install dependencies
flutter pub get

# Configure Firebase
flutterfire configure

# Run on web
flutter run -d chrome
```

---

## ⚙️ Configuration

### 1. Environment Variables

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

2. Edit `functions/.env` with regular environment variables:
```bash
# Email service (Resend)
RESEND_API_KEY=your_resend_api_key_here

# SMS service (Twilio)
TWILIO_ACCOUNT_SID=your_twilio_account_sid
TWILIO_AUTH_TOKEN=your_twilio_auth_token
TWILIO_PHONE_NUMBER=+1234567890

# LiveKit URL (non-secret)
LIVEKIT_URL=wss://your-project.livekit.cloud

# IMPORTANT: LIVEKIT_API_KEY and LIVEKIT_API_SECRET are managed by
# Firebase Secret Manager and should NOT be in this file.
```

**Important:**
- Both `.env` files are git-ignored and never committed
- `.env.example` files provide templates for each environment
- Client `.env` contains ONLY domain-restricted/public keys
- Server `functions/.env` contains most server-side secrets
- **LiveKit API credentials use Firebase Secret Manager** (see below)

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

### 3. Firebase Secret Manager

For sensitive API credentials that should never be exposed in code or regular environment variables, we use Firebase Secret Manager.

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

4. Add **WebSocket URL** to `functions/.env` (server-side):
```bash
LIVEKIT_URL=wss://your-project.livekit.cloud
```

5. Add **API credentials** to Firebase Secret Manager (see Section 3):
```bash
cd functions
echo -n "your_api_key" | firebase functions:secrets:set LIVEKIT_API_KEY
echo -n "your_api_secret" | firebase functions:secrets:set LIVEKIT_API_SECRET
```

**Security Architecture:**
- Client app: Only knows the WebSocket URL (public, safe)
- Cloud Functions: Access API Key/Secret from Firebase Secret Manager
- Token generation happens server-side with secured credentials
- Credentials never exposed in client code or version control
- Local development uses `functions/.env.local` (git-ignored)

---

## 🏃 Running the Application

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

## 🧪 Testing

```bash
# Run all tests (42 tests)
flutter test

# Run with coverage
flutter test --coverage
```

### Test Coverage
- ✅ **Model Tests**: 18 tests (MedicalInfo, EmergencyAlert)
- ✅ **Validator Tests**: 24 tests (Email, Password, Phone, Name)
- **Total**: 42 tests passing

---

## 📊 Project Statistics

**Total Lines of Code: 28,213**

- **Dart (Core Application):** 16,782 lines across 60 files
- **JavaScript (Firebase Functions):** 1,337 lines across 14 files
- **Documentation:** 7,027 lines across 15 Markdown files
- **Platform Code:** 1,754 lines (C++, Swift, Kotlin, XML)
- **Configuration:** 1,313 lines (JSON, YAML, CMake, Gradle)

For detailed statistics, see [LINES_OF_CODE.md](LINES_OF_CODE.md) or run:
```bash
./count_lines.sh
```

---

## 📁 Project Structure

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

## 🏗️ Architecture

For detailed architecture documentation with diagrams, see [ARCHITECTURE.md](ARCHITECTURE.md).

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

## 🔒 Security

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
   - Server `functions/.env`: Regular environment variables (Twilio, Resend, LiveKit URL)
   - **Firebase Secret Manager**: Most sensitive credentials (LiveKit API Key/Secret)
   - Local development: `functions/.env.local` for testing (git-ignored)
   - Production: Secrets accessed via `defineSecret()` in Cloud Functions
   - All sensitive files git-ignored and never committed to version control

---

## 🌐 Deployment

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

## 🐛 Troubleshooting

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

## 📊 Features Breakdown

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

## 🎓 Academic Documentation

This project demonstrates:
- ✅ **Software Engineering**: Service-oriented architecture, separation of concerns
- ✅ **Security**: End-to-end encryption, 2FA, secure authentication
- ✅ **Real-time Systems**: WebRTC, Firestore real-time sync
- ✅ **Cross-platform Development**: Flutter multi-platform support
- ✅ **Testing**: 42 unit tests with comprehensive coverage
- ✅ **Documentation**: Architecture diagrams, code comments, README

### Repository Contents
- `ARCHITECTURE.md`: Comprehensive architecture documentation with 8 Mermaid diagrams
- `test/`: Unit tests for models and validators (42 tests)
- `lib/`: Well-structured codebase with clear separation of concerns
- Commit history showing iterative development

---

## 📚 Technology Stack

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

## 📞 Support & Contact

For academic inquiries or project evaluation:
- **Documentation**: See `ARCHITECTURE.md` for technical details
- **Tests**: Run `flutter test` to verify functionality
- **Demo**: Deploy to web with `flutter build web`

---

## 🙏 Acknowledgments

- Flutter Team for the framework
- Firebase for backend infrastructure
- LiveKit for WebRTC services
- Google Maps for mapping services
- University supervisor for guidance

---

## 📄 License

Academic Project - Final Year 2024/2025

All rights reserved for academic evaluation purposes.

---

**Version:** 1.0.0
**Last Updated:** December 29, 2025
**Flutter:** 3.9.2
**Dart:** 3.9.2

Made with ❤️ for Final Year Project
