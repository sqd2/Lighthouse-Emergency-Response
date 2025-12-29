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

The application uses a `.env` file to manage API keys and configuration. This keeps sensitive information out of version control.

**Setup:**

1. Copy the example file:
```bash
cp .env.example .env
```

2. Edit `.env` and add your actual API keys:
```bash
# Google Maps API Key
GOOGLE_MAPS_API_KEY=your_google_maps_api_key_here

# LiveKit Configuration
LIVEKIT_URL=wss://your-project.livekit.cloud
LIVEKIT_API_KEY=your_livekit_api_key_here
LIVEKIT_API_SECRET=your_livekit_api_secret_here
```

**Important:**
- The `.env` file is git-ignored and never committed to version control
- `.env.example` provides a template showing which keys are needed
- Default values are provided as fallback, but should be replaced with your own keys for production

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

### 3. Google Maps API

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

### 4. LiveKit Configuration

1. Sign up at [LiveKit Cloud](https://cloud.livekit.io/)
2. Create a new project
3. Add your LiveKit credentials to `.env`:
```bash
LIVEKIT_URL=wss://your-project.livekit.cloud
LIVEKIT_API_KEY=your_api_key
LIVEKIT_API_SECRET=your_api_secret
```

**Note:** LiveKit API credentials in `.env` are used by Cloud Functions for generating access tokens. The client app only needs the `LIVEKIT_URL`.

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

5. **Environment Variables**
   - API keys stored in `.env` file (git-ignored)
   - Never committed to version control
   - Template provided via `.env.example`
   - Server-side secrets in Firebase Functions environment

---

## 🌐 Deployment

### Firebase Hosting (Web PWA)

```bash
# Build
flutter build web --release

# Deploy
firebase deploy --only hosting

# Access at: https://your-project.web.app
```

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
**Last Updated:** December 29, 2024
**Flutter:** 3.9.2
**Dart:** 3.9.2

Made with ❤️ for Final Year Project
