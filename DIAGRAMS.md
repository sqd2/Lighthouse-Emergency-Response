# Lighthouse System - Comprehensive Diagrams

This document provides detailed visual diagrams for the Lighthouse Emergency Response System, complementing the architecture documentation in [ARCHITECTURE.md](ARCHITECTURE.md).

## Table of Contents
1. [System Design Diagram](#system-design-diagram)
2. [Use Case Diagram](#use-case-diagram)
3. [Complete WebRTC Call Flow](#complete-webrtc-call-flow)
4. [Analytics Dashboard Data Flow](#analytics-dashboard-data-flow)
5. [Secrets Management Architecture](#secrets-management-architecture)
6. [Two-Factor Authentication Setup Flow](#two-factor-authentication-setup-flow)
7. [Component and Service Dependencies](#component-and-service-dependencies)
8. [Cloud Functions Architecture](#cloud-functions-architecture)
9. [SMS/Email Delivery Flow](#smsemail-delivery-flow)
10. [Complete User Journey](#complete-user-journey)

---

## System Design Diagram

### Complete System Architecture Overview

```mermaid
graph TB
    subgraph "Client Platforms"
        subgraph "Mobile Apps"
            Android[Android App<br/>Flutter 3.9.2]
            iOS[iOS App<br/>Flutter 3.9.2]
        end

        subgraph "Web & Desktop"
            PWA[Progressive Web App<br/>Flutter Web]
            Desktop[Desktop Apps<br/>Windows/macOS/Linux]
        end
    end

    subgraph "Presentation Layer - Flutter"
        subgraph "Citizen UI"
            CitizenDash[Citizen Dashboard<br/>- SOS Button<br/>- Map View<br/>- Medical Info]
            CitizenScreens[Screens:<br/>- Profile<br/>- Settings<br/>- 2FA Setup<br/>- Alert History]
        end

        subgraph "Dispatcher UI"
            DispatcherDash[Dispatcher Dashboard<br/>- Alert Feed<br/>- Analytics<br/>- Map View]
            DispatcherScreens[Screens:<br/>- Profile<br/>- Settings<br/>- Facility Management]
        end

        subgraph "Shared UI"
            CallScreen[Call Screen<br/>Video/Audio UI]
            ChatScreen[Chat Screen<br/>Real-time Messages]
            AuthScreens[Auth Screens:<br/>- Login<br/>- 2FA Gate<br/>- 2FA Verify]
        end
    end

    subgraph "Business Logic Layer - Services"
        subgraph "Core Services"
            TwoFactorSvc[TwoFactorService<br/>TOTP + Email 2FA]
            EncryptionSvc[EncryptionService<br/>AES-256-CBC]
            MedicalInfoSvc[MedicalInfoService<br/>Encrypted CRUD]
        end

        subgraph "Communication Services"
            LiveKitSvc[LiveKitService<br/>WebRTC Calls]
            NotificationSvc[NotificationService<br/>FCM Push]
        end

        subgraph "Location Services"
            PlacesSvc[PlacesService<br/>Facility Search]
            DirectionsSvc[DirectionsService<br/>Route Calculation]
        end

        subgraph "Data Services"
            AnalyticsSvc[AnalyticsService<br/>Metrics Aggregation]
            AlertHistorySvc[AlertHistoryService<br/>Alert CRUD]
        end
    end

    subgraph "Data Models Layer"
        Models[Data Models:<br/>- EmergencyAlert<br/>- MedicalInfo<br/>- Call<br/>- ChatMessage<br/>- FacilityPin]
    end

    subgraph "Firebase Backend"
        subgraph "Authentication & Authorization"
            FirebaseAuth[Firebase Authentication<br/>Email/Password<br/>JWT Tokens]
        end

        subgraph "Data Storage"
            Firestore[(Cloud Firestore<br/>NoSQL Database<br/>Real-time Sync)]
            FirebaseStorage[(Firebase Storage<br/>Media Files<br/>Photos/Videos)]
        end

        subgraph "Serverless Computing"
            CloudFunctions[Cloud Functions<br/>Node.js Runtime]

            subgraph "Function Endpoints"
                TokenFunc[generateLiveKitToken<br/>JWT Generation]
                EmailFunc[sendEmail<br/>Resend API]
                SMSFunc[sendSMS<br/>Twilio API]
            end
        end

        subgraph "Messaging & Secrets"
            FCM[Firebase Cloud<br/>Messaging<br/>Push Notifications]
            SecretManager[Firebase Secret<br/>Manager<br/>API Credentials]
        end
    end

    subgraph "External Services"
        subgraph "Real-time Communication"
            LiveKitCloud[LiveKit Cloud<br/>WebRTC SFU Server<br/>Media Relay]
        end

        subgraph "Location & Maps"
            GoogleMaps[Google Maps API<br/>Map Rendering]
            GooglePlaces[Google Places API<br/>Facility Search]
            GoogleDirections[Google Directions API<br/>Route Calculation]
        end

        subgraph "Communication APIs"
            Twilio[Twilio API<br/>SMS Delivery]
            Resend[Resend API<br/>Email Delivery]
        end
    end

    subgraph "Infrastructure"
        subgraph "Hosting & CDN"
            FirebaseHosting[Firebase Hosting<br/>Global CDN<br/>SSL/TLS]
            ServiceWorker[Service Worker<br/>Offline Support<br/>PWA Cache]
        end

        subgraph "Security"
            HTTPS[HTTPS/TLS 1.3<br/>All Communications]
            SRTP[SRTP<br/>Encrypted Media]
            SecurityRules[Firestore Security Rules<br/>RBAC]
        end
    end

    %% Client to Presentation
    Android --> CitizenDash
    iOS --> CitizenDash
    PWA --> CitizenDash
    PWA --> DispatcherDash
    Desktop --> DispatcherDash

    %% Presentation to Business Logic
    CitizenDash --> TwoFactorSvc
    CitizenDash --> MedicalInfoSvc
    CitizenDash --> PlacesSvc
    CitizenDash --> DirectionsSvc
    CitizenDash --> AlertHistorySvc

    DispatcherDash --> AnalyticsSvc
    DispatcherDash --> AlertHistorySvc
    DispatcherDash --> PlacesSvc

    CallScreen --> LiveKitSvc
    ChatScreen --> NotificationSvc
    AuthScreens --> TwoFactorSvc

    %% Business Logic to Data Models
    TwoFactorSvc --> Models
    MedicalInfoSvc --> Models
    LiveKitSvc --> Models
    AnalyticsSvc --> Models
    AlertHistorySvc --> Models

    %% Business Logic to Backend
    TwoFactorSvc --> FirebaseAuth
    TwoFactorSvc --> Firestore
    TwoFactorSvc --> CloudFunctions

    EncryptionSvc --> FirebaseAuth
    MedicalInfoSvc --> EncryptionSvc
    MedicalInfoSvc --> Firestore

    LiveKitSvc --> Firestore
    LiveKitSvc --> CloudFunctions
    NotificationSvc --> FCM
    NotificationSvc --> Firestore

    AnalyticsSvc --> Firestore
    AlertHistorySvc --> Firestore
    AlertHistorySvc --> FirebaseStorage

    %% Cloud Functions to Secrets
    TokenFunc --> SecretManager
    EmailFunc --> SecretManager
    SMSFunc --> SecretManager

    CloudFunctions --> TokenFunc
    CloudFunctions --> EmailFunc
    CloudFunctions --> SMSFunc

    %% Cloud Functions to External APIs
    TokenFunc --> LiveKitCloud
    EmailFunc --> Resend
    SMSFunc --> Twilio

    %% Services to External APIs
    LiveKitSvc --> LiveKitCloud
    PlacesSvc --> GooglePlaces
    DirectionsSvc --> GoogleDirections
    CitizenDash --> GoogleMaps
    DispatcherDash --> GoogleMaps

    %% Hosting
    PWA --> FirebaseHosting
    FirebaseHosting --> ServiceWorker

    %% Security Layer
    HTTPS --> FirebaseAuth
    HTTPS --> Firestore
    HTTPS --> CloudFunctions
    SRTP --> LiveKitCloud
    SecurityRules --> Firestore

    %% Styling
    style Android fill:#3DDC84
    style iOS fill:#007AFF
    style PWA fill:#4285F4
    style Firestore fill:#FFA000
    style LiveKitCloud fill:#00D4AA
    style SecretManager fill:#EA4335
    style EncryptionSvc fill:#34A853
    style TwoFactorSvc fill:#EA4335
    style AnalyticsSvc fill:#FBBC04
```

### System Technology Stack Breakdown

```mermaid
graph LR
    subgraph "Frontend Stack"
        F1[Flutter 3.9.2<br/>Dart 3.9.2]
        F2[Material Design<br/>UI Components]
        F3[fl_chart<br/>Analytics Charts]
        F4[google_maps_flutter<br/>Map Integration]
        F5[livekit_client<br/>WebRTC SDK]
    end

    subgraph "Backend Stack"
        B1[Firebase Auth<br/>Authentication]
        B2[Cloud Firestore<br/>NoSQL Database]
        B3[Firebase Storage<br/>Blob Storage]
        B4[Cloud Functions<br/>Node.js 18]
        B5[Firebase Hosting<br/>Static Hosting]
    end

    subgraph "Security Stack"
        S1[encrypt package<br/>AES-256-CBC]
        S2[pointycastle<br/>SHA-256 Hashing]
        S3[otp package<br/>TOTP Generator]
        S4[Firebase Secret<br/>Manager]
    end

    subgraph "External APIs"
        E1[LiveKit Cloud<br/>WebRTC Infrastructure]
        E2[Google Maps APIs<br/>Maps/Places/Directions]
        E3[Twilio API<br/>SMS Gateway]
        E4[Resend API<br/>Email Service]
    end

    F1 --> B1
    F1 --> B2
    F1 --> B3
    F1 --> B5

    B4 --> S4
    B4 --> E1
    B4 --> E3
    B4 --> E4

    F1 --> S1
    F1 --> S2
    F1 --> S3

    F5 --> E1
    F4 --> E2

    style F1 fill:#4285F4
    style B2 fill:#FFA000
    style S1 fill:#34A853
    style E1 fill:#00D4AA
```

### Data Flow and Communication Patterns

```mermaid
graph TB
    subgraph "Real-time Data Flows"
        RT1[Emergency Alerts<br/>Real-time Sync]
        RT2[Location Updates<br/>GPS Streaming]
        RT3[Call Status<br/>WebRTC Signaling]
        RT4[Chat Messages<br/>Real-time Chat]
    end

    subgraph "Request-Response Flows"
        RR1[2FA Code Generation<br/>HTTP Callable]
        RR2[LiveKit Token<br/>HTTP Callable]
        RR3[Analytics Queries<br/>Firestore Queries]
        RR4[Facility Search<br/>Google Places API]
    end

    subgraph "Event-Driven Flows"
        ED1[Alert Created<br/>→ FCM Notification]
        ED2[Call Initiated<br/>→ Push Notification]
        ED3[Alert Accepted<br/>→ Update UI]
        ED4[Location Changed<br/>→ Update Map]
    end

    subgraph "Batch Operations"
        BO1[Analytics Aggregation<br/>7-day Trend]
        BO2[Top Dispatchers<br/>Ranking Query]
        BO3[Alert History<br/>Paginated List]
    end

    Firestore[(Firestore)] --> RT1
    Firestore --> RT2
    Firestore --> RT3
    Firestore --> RT4

    CloudFunc[Cloud Functions] --> RR1
    CloudFunc --> RR2
    Firestore --> RR3
    GoogleAPI[Google APIs] --> RR4

    FCM[FCM] --> ED1
    FCM --> ED2
    Firestore --> ED3
    GPS[GPS Service] --> ED4

    Firestore --> BO1
    Firestore --> BO2
    Firestore --> BO3

    style Firestore fill:#FFA000
    style CloudFunc fill:#FBBC04
    style FCM fill:#EA4335
    style GoogleAPI fill:#4285F4
```

---

## Use Case Diagram

### System Actors

```mermaid
graph LR
    Citizen((Citizen<br/>User))
    Dispatcher((Dispatcher<br/>User))

    style Citizen fill:#4285F4,color:#fff
    style Dispatcher fill:#9C27B0,color:#fff
```

**Actor Descriptions:**
- **Citizen User**: End-user who creates emergency alerts and interacts with dispatchers
- **Dispatcher User**: Emergency response personnel who manage and respond to alerts

**Note:** System automated processes (encryption, notifications, token generation, etc.) are shown as dependencies using dotted lines in the diagrams below. They are not actors but rather internal system behaviors triggered by user actions.

---

### 1. Authentication & User Management Use Cases

```mermaid
graph LR
    Citizen((Citizen))
    Dispatcher((Dispatcher))

    UC1[Register Account]
    UC2[Login]
    UC3[Enable 2FA]
    UC4[Verify 2FA Code]
    UC5[Logout]
    UC17[Update Profile]
    UC18[Change Password]

    Citizen --> UC1
    Citizen --> UC2
    Citizen --> UC3
    Citizen --> UC4
    Citizen --> UC5
    Citizen --> UC17
    Citizen --> UC18

    Dispatcher --> UC1
    Dispatcher --> UC2
    Dispatcher --> UC3
    Dispatcher --> UC4
    Dispatcher --> UC5
    Dispatcher --> UC17
    Dispatcher --> UC18

    UC3 -.->|triggers| SendEmail[System: Send 2FA Email]
    UC3 -.->|triggers| SendSMS[System: Send 2FA SMS]
    UC4 -.->|verifies| SendEmail
    UC4 -.->|verifies| SendSMS

    style Citizen fill:#4285F4,color:#fff
    style Dispatcher fill:#9C27B0,color:#fff
    style UC1 fill:#f9f9f9
    style UC2 fill:#f9f9f9
    style UC3 fill:#f9f9f9
    style UC4 fill:#f9f9f9
    style UC5 fill:#f9f9f9
    style UC17 fill:#f9f9f9
    style UC18 fill:#f9f9f9
    style SendEmail fill:#34A853,color:#fff
    style SendSMS fill:#34A853,color:#fff
```

---

### 2. Citizen Emergency Alert Use Cases

```mermaid
graph TB
    Citizen((Citizen))

    UC6[Create Emergency Alert]
    UC7[Add Description & Media]
    UC8[Track Alert Status]
    UC11[View Dispatcher Location]
    UC12[Cancel Alert]
    UC13[View Alert History]

    Citizen --> UC6
    Citizen --> UC7
    Citizen --> UC8
    Citizen --> UC11
    Citizen --> UC12
    Citizen --> UC13

    UC6 -.->|requires| GPS[System: GPS Tracking]
    UC6 -.->|triggers| Notify[System: Send FCM Notification]
    UC7 -.->|extends| UC6
    UC11 -.->|requires| Sync[System: Sync Location Updates]

    style Citizen fill:#4285F4,color:#fff
    style UC6 fill:#EA4335,color:#fff
    style UC7 fill:#f9f9f9
    style UC8 fill:#f9f9f9
    style UC11 fill:#f9f9f9
    style UC12 fill:#f9f9f9
    style UC13 fill:#f9f9f9
    style GPS fill:#34A853,color:#fff
    style Notify fill:#34A853,color:#fff
    style Sync fill:#34A853,color:#fff
```

---

### 3. Citizen Medical Information Use Cases

```mermaid
graph LR
    Citizen((Citizen))

    UC14[Add Medical Info]
    UC15[Update Medical Info]
    UC16[View Medical Info]

    Citizen --> UC14
    Citizen --> UC15
    Citizen --> UC16

    UC14 -.->|requires| Encrypt[System: Encrypt Medical Data<br/>AES-256-CBC]
    UC15 -.->|requires| Encrypt
    UC16 -.->|requires| Decrypt[System: Decrypt Medical Data]

    style Citizen fill:#4285F4,color:#fff
    style UC14 fill:#f9f9f9
    style UC15 fill:#f9f9f9
    style UC16 fill:#f9f9f9
    style Encrypt fill:#34A853,color:#fff
    style Decrypt fill:#34A853,color:#fff
```

---

### 4. Citizen Location & Facility Use Cases

```mermaid
graph LR
    Citizen((Citizen))

    UC20[Search for Facilities]
    UC21[View Facility Details]
    UC22[Navigate to Facility]
    UC23[View Current Location]

    Citizen --> UC20
    Citizen --> UC21
    Citizen --> UC22
    Citizen --> UC23

    UC20 -.->|uses| Places[Google Places API]
    UC22 -.->|uses| Directions[Google Directions API]
    UC23 -.->|uses| GPS[GPS Service]

    style Citizen fill:#4285F4,color:#fff
    style UC20 fill:#f9f9f9
    style UC21 fill:#f9f9f9
    style UC22 fill:#f9f9f9
    style UC23 fill:#f9f9f9
    style Places fill:#FBBC04,color:#000
    style Directions fill:#FBBC04,color:#000
    style GPS fill:#34A853,color:#fff
```

---

### 5. Dispatcher Alert Management Use Cases

```mermaid
graph TB
    Dispatcher((Dispatcher))

    UC24[View Emergency Alerts Feed]
    UC25[Accept Emergency Alert]
    UC26[View Alert Details]
    UC27[View Citizen Medical Info]
    UC30[Mark as Arrived]
    UC31[Mark as Resolved]
    UC32[View Alert History]

    Dispatcher --> UC24
    Dispatcher --> UC25
    Dispatcher --> UC26
    Dispatcher --> UC27
    Dispatcher --> UC30
    Dispatcher --> UC31
    Dispatcher --> UC32

    UC25 -.->|triggers| Sync[System: Sync Location Updates]
    UC27 -.->|requires| Decrypt[System: Decrypt Medical Data]
    UC31 -.->|includes| AddNotes[Add Resolution Notes]

    style Dispatcher fill:#9C27B0,color:#fff
    style UC24 fill:#f9f9f9
    style UC25 fill:#FBBC04,color:#000
    style UC26 fill:#f9f9f9
    style UC27 fill:#f9f9f9
    style UC30 fill:#f9f9f9
    style UC31 fill:#f9f9f9
    style UC32 fill:#f9f9f9
    style Sync fill:#34A853,color:#fff
    style Decrypt fill:#34A853,color:#fff
    style AddNotes fill:#f9f9f9
```

---

### 6. Dispatcher Analytics & Facility Management Use Cases

```mermaid
graph LR
    Dispatcher((Dispatcher))

    UC33[View Analytics Dashboard]
    UC34[View Total Alerts]
    UC35[View Response Times]
    UC36[View Success Rate]
    UC37[View Top Dispatchers]
    UC38[Add Facility Pin]
    UC39[View Facilities on Map]

    Dispatcher --> UC33
    Dispatcher --> UC38
    Dispatcher --> UC39

    UC33 --> UC34
    UC33 --> UC35
    UC33 --> UC36
    UC33 --> UC37

    UC34 -.->|uses| Analytics[System: Aggregate Analytics]
    UC35 -.->|uses| Analytics
    UC36 -.->|uses| Analytics
    UC37 -.->|uses| Analytics

    style Dispatcher fill:#9C27B0,color:#fff
    style UC33 fill:#FBBC04,color:#000
    style UC34 fill:#f9f9f9
    style UC35 fill:#f9f9f9
    style UC36 fill:#f9f9f9
    style UC37 fill:#f9f9f9
    style UC38 fill:#f9f9f9
    style UC39 fill:#f9f9f9
    style Analytics fill:#34A853,color:#fff
```

---

### 7. WebRTC Video/Audio Call Use Cases

```mermaid
graph TB
    Citizen((Citizen))
    Dispatcher((Dispatcher))

    UC40[Start Call]
    UC41[Accept Call]
    UC42[Decline Call]
    UC43[Toggle Mute]
    UC44[Toggle Video]
    UC45[End Call]
    UC9[Receive Incoming Call]
    UC10[Chat with Other Party]

    Dispatcher --> UC40
    Dispatcher --> UC41
    Dispatcher --> UC42
    Dispatcher --> UC43
    Dispatcher --> UC44
    Dispatcher --> UC45
    Dispatcher --> UC10

    Citizen --> UC9
    Citizen --> UC41
    Citizen --> UC42
    Citizen --> UC43
    Citizen --> UC44
    Citizen --> UC45
    Citizen --> UC10

    UC40 -.->|requires| Token[System: Generate LiveKit Token]
    UC9 -.->|requires| Token
    UC40 -.->|creates| UC9

    style Citizen fill:#4285F4,color:#fff
    style Dispatcher fill:#9C27B0,color:#fff
    style UC40 fill:#00D4AA,color:#fff
    style UC41 fill:#f9f9f9
    style UC42 fill:#f9f9f9
    style UC43 fill:#f9f9f9
    style UC44 fill:#f9f9f9
    style UC45 fill:#f9f9f9
    style UC9 fill:#00D4AA,color:#fff
    style UC10 fill:#f9f9f9
    style Token fill:#34A853,color:#fff
```

---

### Use Case Descriptions Table

| Use Case ID | Use Case Name | Actor | Description | Preconditions |
|-------------|---------------|-------|-------------|---------------|
| **UC1** | Register Account | Citizen, Dispatcher | Create new account with email, password, name, phone, role | None |
| **UC2** | Login | Citizen, Dispatcher | Authenticate with email and password | Account exists |
| **UC3** | Enable 2FA | Citizen, Dispatcher | Setup TOTP or email-based 2FA | Logged in |
| **UC4** | Verify 2FA Code | Citizen, Dispatcher | Enter 6-digit verification code | 2FA enabled, code sent |
| **UC5** | Logout | Citizen, Dispatcher | Sign out and clear session | Logged in |
| **UC6** | Create Emergency Alert | Citizen | Create SOS alert with location and services | Logged in, GPS enabled |
| **UC7** | Add Alert Description | Citizen | Add text description and upload media | Alert created |
| **UC8** | Track Alert Status | Citizen | Monitor alert status changes in real-time | Alert exists |
| **UC9** | Receive Call | Citizen | Accept/decline incoming call from dispatcher | Alert active, dispatcher calls |
| **UC10** | Chat with Dispatcher | Citizen | Send/receive real-time messages | Alert active |
| **UC11** | View Dispatcher Location | Citizen | Track dispatcher's GPS location on map | Alert accepted |
| **UC12** | Cancel Alert | Citizen | Cancel emergency alert before resolution | Alert pending/active |
| **UC13** | View Alert History | Citizen | Browse past emergency alerts | Logged in |
| **UC14** | Add Medical Info | Citizen | Enter medical information (encrypted) | Logged in |
| **UC15** | Update Medical Info | Citizen | Modify existing medical information | Medical info exists |
| **UC16** | View Medical Info | Citizen | View decrypted medical information | Medical info exists |
| **UC17** | Update Profile | Citizen, Dispatcher | Modify name, phone, email | Logged in |
| **UC18** | Change Password | Citizen, Dispatcher | Update account password | Logged in |
| **UC19** | Configure 2FA | Citizen, Dispatcher | Enable/disable 2FA, change method | Logged in |
| **UC20** | Search Facilities | Citizen | Find nearby hospitals, police, fire stations | GPS enabled |
| **UC21** | View Facility Details | Citizen | See facility address, phone, hours | Facility selected |
| **UC22** | Navigate to Facility | Citizen | Get directions to emergency facility | Facility selected, GPS enabled |
| **UC23** | View Current Location | Citizen | Display current GPS coordinates on map | GPS enabled |
| **UC24** | View Emergency Alerts | Dispatcher | See real-time feed of pending alerts | Logged in as dispatcher |
| **UC25** | Accept Alert | Dispatcher | Accept and assign alert to self | Alert pending |
| **UC26** | View Alert Details | Dispatcher | See alert location, services, media | Alert exists |
| **UC27** | View Citizen Medical Info | Dispatcher | Access encrypted medical information | Alert accepted |
| **UC28** | Initiate Call | Dispatcher | Start video/audio call to citizen | Alert accepted |
| **UC29** | Chat with Citizen | Dispatcher | Send/receive real-time messages | Alert active |
| **UC30** | Mark as Arrived | Dispatcher | Update status when arriving on scene | En route to site |
| **UC31** | Mark as Resolved | Dispatcher | Close alert with resolution notes | On-site, situation handled |
| **UC32** | View Alert History | Dispatcher | Browse all past alerts system-wide | Logged in as dispatcher |
| **UC33** | View Analytics Dashboard | Dispatcher | See metrics, charts, statistics | Logged in as dispatcher |
| **UC34** | View Total Alerts | Dispatcher | See alert count for time period | Analytics dashboard |
| **UC35** | View Response Times | Dispatcher | See average response time metrics | Analytics dashboard |
| **UC36** | View Success Rate | Dispatcher | See percentage of resolved alerts | Analytics dashboard |
| **UC37** | View Top Dispatchers | Dispatcher | See leaderboard of top performers | Analytics dashboard |
| **UC38** | Add Facility Pin | Dispatcher | Manually add emergency facility | Logged in as dispatcher |
| **UC39** | View Facilities on Map | Dispatcher | See all facilities on map | Logged in as dispatcher |
| **UC40** | Start Call | Dispatcher | Initiate video/audio call | Alert accepted |
| **UC41** | Accept Call | Citizen, Dispatcher | Accept incoming call | Call ringing |
| **UC42** | Decline Call | Citizen, Dispatcher | Reject incoming call | Call ringing |
| **UC43** | Toggle Mute | Citizen, Dispatcher | Mute/unmute microphone | In active call |
| **UC44** | Toggle Video | Citizen, Dispatcher | Enable/disable camera | In active call |
| **UC45** | End Call | Citizen, Dispatcher | Terminate active call | In active call |

**Total Use Cases:** 45 use cases across 7 functional areas

**Note:** System automated processes (encryption, notifications, token generation, location sync, analytics, security rules) are not separate use cases but rather internal system behaviors that support the user-facing use cases listed above. These are shown as dependencies in the diagrams with dotted lines.

---

## Complete WebRTC Call Flow

### End-to-End Call Sequence (Dispatcher → Citizen)

```mermaid
sequenceDiagram
    participant D as Dispatcher App
    participant DFS as Firestore<br/>(Dispatcher Side)
    participant CF as Cloud Functions
    participant LKS as LiveKit Server
    participant CFS as Firestore<br/>(Citizen Side)
    participant C as Citizen App
    participant FCM as Firebase Cloud<br/>Messaging

    Note over D: Dispatcher views alert<br/>and clicks "Call"

    D->>DFS: Create call document<br/>(status: ringing)
    DFS->>CFS: Real-time sync

    D->>CF: Request LiveKit token<br/>(HTTP: generateLiveKitToken)
    Note over CF: Validate request<br/>Check auth token

    CF->>CF: Access Firebase Secret Manager<br/>(LIVEKIT_API_KEY,<br/>LIVEKIT_API_SECRET)
    CF->>CF: Generate JWT token<br/>with room permissions
    CF-->>D: Return token

    CFS-->>C: Call document update<br/>(real-time listener)
    C->>C: Show incoming call dialog<br/>"Dispatcher calling..."

    CFS->>FCM: Trigger notification
    FCM-->>C: Push notification<br/>"Incoming emergency call"

    alt User Accepts Call
        C->>CFS: Update call status<br/>(status: connecting)
        CFS->>DFS: Real-time sync
        DFS-->>D: Status update

        C->>CF: Request LiveKit token<br/>(HTTP: generateLiveKitToken)
        CF->>CF: Access Firebase secrets
        CF->>CF: Generate JWT token
        CF-->>C: Return token

        par Join Room (Both Sides)
            D->>LKS: Connect with token<br/>Room: alert_{alertId}
            C->>LKS: Connect with token<br/>Room: alert_{alertId}
        end

        LKS->>LKS: Establish WebRTC<br/>SFU connection

        par Media Tracks
            D->>LKS: Publish audio/video track
            C->>LKS: Publish audio/video track
        end

        LKS-->>D: Subscribe to remote tracks
        LKS-->>C: Subscribe to remote tracks

        par Update Call Status
            D->>DFS: Update status: active
            C->>CFS: Update status: active
        end

        Note over D,C: Live audio/video call<br/>(SRTP encrypted)

        alt Dispatcher Ends Call
            D->>D: User clicks "End Call"<br/>Show confirmation
            D->>DFS: Update call<br/>(status: ended,<br/>endedAt: timestamp)
            D->>LKS: Disconnect from room
            DFS->>CFS: Real-time sync
            CFS-->>C: Call ended notification
            C->>C: Close call screen
            C->>LKS: Disconnect from room
        else Citizen Ends Call
            C->>C: User clicks "End Call"<br/>Show confirmation
            C->>CFS: Update call<br/>(status: ended,<br/>endedAt: timestamp)
            C->>LKS: Disconnect from room
            CFS->>DFS: Real-time sync
            DFS-->>D: Call ended notification
            D->>D: Close call screen
            D->>LKS: Disconnect from room
        end

    else User Rejects Call
        C->>CFS: Update call status<br/>(status: rejected,<br/>endedAt: timestamp)
        CFS->>DFS: Real-time sync
        DFS-->>D: "Call declined"
        D->>D: Show snackbar notification
    end

    Note over D,C: Call complete
```

---

## Analytics Dashboard Data Flow

### Analytics Data Aggregation and Display

```mermaid
graph TB
    subgraph "Data Sources"
        Alerts[(emergency_alerts<br/>collection)]
        Users[(users<br/>collection)]
        Calls[(calls<br/>subcollection)]
    end

    subgraph "Analytics Service Queries"
        Q1[getTotalAlerts<br/>WHERE createdAt >= startDate]
        Q2[getAlertsByStatus<br/>GROUP BY status]
        Q3[getAverageResponseTime<br/>acceptedAt - createdAt]
        Q4[getAlertTrend<br/>GROUP BY date]
        Q5[getTopDispatchers<br/>COUNT resolved alerts]
        Q6[getActiveDispatchersCount<br/>WHERE role=dispatcher<br/>AND isActive=true]
        Q7[getSuccessRate<br/>resolved / total]
    end

    subgraph "Data Processing"
        P1[Aggregate by date]
        P2[Calculate averages]
        P3[Sort & rank]
        P4[Format percentages]
    end

    subgraph "UI Components"
        M1[Metric Cards<br/>4 cards in grid]
        C1[Pie Chart<br/>Alert Status Breakdown]
        C2[Line Chart<br/>7-day Trend]
        L1[Leaderboard<br/>Top 5 Dispatchers]
    end

    Alerts --> Q1
    Alerts --> Q2
    Alerts --> Q3
    Alerts --> Q4
    Alerts --> Q5
    Alerts --> Q7
    Users --> Q6

    Q1 --> M1
    Q3 --> P2
    Q2 --> P4
    Q4 --> P1
    Q5 --> P3
    Q6 --> M1
    Q7 --> P4

    P2 --> M1
    P4 --> C1
    P1 --> C2
    P3 --> L1
    P4 --> M1

    style Alerts fill:#EA4335
    style Users fill:#4285F4
    style M1 fill:#34A853
    style C1 fill:#FBBC04
    style C2 fill:#EA4335
    style L1 fill:#4285F4
```

### Analytics Metrics Calculation

```mermaid
flowchart LR
    subgraph "Total Alerts"
        A1[Query alerts<br/>in date range] --> A2[Count documents]
        A2 --> A3[Display count]
    end

    subgraph "Avg Response Time"
        B1[Query alerts<br/>status: active/arrived/resolved] --> B2[Calculate<br/>acceptedAt - createdAt]
        B2 --> B3[Sum all response times]
        B3 --> B4[Divide by count]
        B4 --> B5[Format as<br/>minutes:seconds]
    end

    subgraph "Success Rate"
        C1[Count all alerts<br/>excluding cancelled] --> C2[Count resolved alerts]
        C2 --> C3[Calculate<br/>resolved / total * 100]
        C3 --> C4[Display percentage]
    end

    subgraph "Top Dispatchers"
        D1[Query all resolved alerts] --> D2[Group by<br/>acceptedBy]
        D2 --> D3[Count per dispatcher]
        D3 --> D4[Calculate avg<br/>response time]
        D4 --> D5[Sort by count DESC]
        D5 --> D6[Take top 5]
    end

    style A3 fill:#34A853
    style B5 fill:#4285F4
    style C4 fill:#FBBC04
    style D6 fill:#EA4335
```

---

## Secrets Management Architecture

### Environment Variables and Secrets Flow

```mermaid
graph TB
    subgraph "Development Environment"
        DevEnv[Developer Machine]

        subgraph "Client Config (Root)"
            ClientEnv[.env file<br/>git-ignored]
            ClientExample[.env.example<br/>committed to git]
        end

        subgraph "Server Config (functions/)"
            ServerEnv[functions/.env<br/>git-ignored]
            ServerLocal[functions/.env.local<br/>git-ignored]
            ServerExample[functions/.env.example<br/>committed to git]
        end
    end

    subgraph "Client Application"
        FlutterApp[Flutter App]
        EnvLoader[flutter_dotenv]
    end

    subgraph "Cloud Functions (Local)"
        LocalFunctions[Firebase Emulator]
        LocalEnvLoad[dotenv.config]
    end

    subgraph "Production Environment"
        subgraph "Firebase Hosting"
            WebApp[PWA/Web App]
        end

        subgraph "Cloud Functions (Production)"
            ProdFunctions[Deployed Functions]
            SecretManager[Firebase Secret Manager]
        end

        subgraph "External APIs"
            LiveKit[LiveKit Cloud]
            Twilio[Twilio API]
            Resend[Resend API]
            GMaps[Google Maps API]
        end
    end

    ClientExample -.->|Copy & fill| ClientEnv
    ServerExample -.->|Copy & fill| ServerEnv
    ServerExample -.->|Copy & fill| ServerLocal

    ClientEnv -->|Loaded by| EnvLoader
    EnvLoader -->|Provides| FlutterApp

    ServerLocal -->|Loaded by| LocalEnvLoad
    LocalEnvLoad -->|Provides| LocalFunctions

    ServerEnv -->|Contains| Twilio
    ServerEnv -->|Contains| Resend
    ClientEnv -->|Contains| GMaps

    ProdFunctions -->|Access via<br/>defineSecret| SecretManager
    SecretManager -->|Provides| LiveKit

    FlutterApp -->|API calls| GMaps
    FlutterApp -->|WebSocket| LiveKit
    ProdFunctions -->|Generate tokens| LiveKit
    ProdFunctions -->|Send SMS| Twilio
    ProdFunctions -->|Send Email| Resend

    style ClientEnv fill:#4285F4
    style ServerEnv fill:#34A853
    style ServerLocal fill:#FBBC04
    style SecretManager fill:#EA4335
    style ClientExample fill:#9E9E9E
    style ServerExample fill:#9E9E9E
```

### Secret Categories and Storage

```mermaid
flowchart TB
    subgraph "Public/Domain-Restricted"
        direction LR
        S1[Google Maps API Key<br/>Client .env]
        S2[LiveKit WebSocket URL<br/>Client .env<br/>Server .env]
    end

    subgraph "Regular Environment Variables"
        direction LR
        S3[Twilio Account SID<br/>Server .env]
        S4[Twilio Auth Token<br/>Server .env]
        S5[Twilio Phone Number<br/>Server .env]
        S6[Resend API Key<br/>Server .env]
    end

    subgraph "Firebase Secret Manager"
        direction LR
        S7[LiveKit API Key<br/>Firebase Secret]
        S8[LiveKit API Secret<br/>Firebase Secret]
    end

    subgraph "Access Methods"
        A1[flutter_dotenv.env]
        A2[process.env]
        A3[defineSecret]
    end

    S1 --> A1
    S2 --> A1
    S2 --> A2
    S3 --> A2
    S4 --> A2
    S5 --> A2
    S6 --> A2
    S7 --> A3
    S8 --> A3

    style S1 fill:#4285F4
    style S2 fill:#4285F4
    style S3 fill:#34A853
    style S4 fill:#34A853
    style S5 fill:#34A853
    style S6 fill:#34A853
    style S7 fill:#EA4335
    style S8 fill:#EA4335
```

---

## Two-Factor Authentication Setup Flow

### TOTP (Authenticator App) Setup

```mermaid
sequenceDiagram
    participant U as User
    participant UI as Settings Screen
    participant 2FA as TwoFactorService
    participant FS as Firestore
    participant Auth as Authenticator App<br/>(Google/Authy)

    U->>UI: Navigate to 2FA Settings
    UI->>UI: Show "Enable 2FA" button

    U->>UI: Click "Enable 2FA"
    UI->>UI: Show method selection<br/>(TOTP vs Email)

    U->>UI: Select "Authenticator App"

    UI->>2FA: generateTOTPSecret()
    2FA->>2FA: Generate random 32-char<br/>base32 secret
    2FA-->>UI: Return secret

    UI->>UI: Generate QR code<br/>otpauth://totp/Lighthouse?secret=...
    UI-->>U: Display QR code + manual entry code

    U->>Auth: Open authenticator app
    U->>Auth: Scan QR code or<br/>enter secret manually
    Auth->>Auth: Add "Lighthouse" account
    Auth-->>U: Display 6-digit code

    U->>UI: Enter verification code
    UI->>2FA: verifyTOTPCode(code, secret)
    2FA->>2FA: Generate expected code<br/>for current time window
    2FA->>2FA: Compare codes

    alt Code Valid
        2FA-->>UI: Valid ✓
        UI->>FS: Save 2FA settings<br/>users/{uid}/twoFactor
        Note over FS: {<br/>  enabled: true,<br/>  method: 'totp',<br/>  secret: encrypted_secret,<br/>  enabledAt: timestamp<br/>}
        FS-->>UI: Success
        UI-->>U: "2FA enabled successfully!<br/>Backup codes: ..."
    else Code Invalid
        2FA-->>UI: Invalid ✗
        UI-->>U: "Invalid code. Try again."
        Note over U: User re-enters code<br/>from authenticator
    end
```

### Email-based 2FA Setup

```mermaid
sequenceDiagram
    participant U as User
    participant UI as Settings Screen
    participant 2FA as TwoFactorService
    participant FS as Firestore
    participant CF as Cloud Functions
    participant Email as Email Service<br/>(Resend)

    U->>UI: Navigate to 2FA Settings
    U->>UI: Click "Enable 2FA"
    U->>UI: Select "Email Verification"

    UI->>2FA: Request email verification
    2FA->>2FA: Generate 6-digit code
    2FA->>FS: Store verification code<br/>users/{uid}/emailVerification
    Note over FS: {<br/>  code: "123456",<br/>  expiresAt: now + 5min,<br/>  verified: false<br/>}

    2FA->>CF: Call sendEmail function
    CF->>Email: Send verification email
    Email-->>U: Email with code

    U->>UI: Enter code from email
    UI->>2FA: verifyEmailCode(code)
    2FA->>FS: Query verification code
    FS-->>2FA: Return code + expiry

    2FA->>2FA: Check expiry<br/>(now < expiresAt?)
    2FA->>2FA: Compare codes

    alt Code Valid & Not Expired
        2FA-->>UI: Valid ✓
        UI->>FS: Save 2FA settings<br/>users/{uid}/twoFactor
        Note over FS: {<br/>  enabled: true,<br/>  method: 'email',<br/>  enabledAt: timestamp<br/>}
        FS->>FS: Delete verification code
        UI-->>U: "Email 2FA enabled!"
    else Code Invalid or Expired
        2FA-->>UI: Invalid ✗
        UI-->>U: "Code invalid or expired"
        Note over U: User can request<br/>new code
    end
```

### 2FA Login Gate Flow

```mermaid
flowchart TB
    Start([User Logs In]) --> FirebaseAuth[Firebase Auth<br/>Email + Password]
    FirebaseAuth --> AuthSuccess{Auth<br/>Successful?}

    AuthSuccess -->|No| ShowError[Show Error Message]
    ShowError --> End1([End])

    AuthSuccess -->|Yes| Check2FA[Check Firestore<br/>users/{uid}/twoFactor]
    Check2FA --> Is2FAEnabled{2FA<br/>Enabled?}

    Is2FAEnabled -->|No| Dashboard[Navigate to Dashboard]
    Dashboard --> End2([End])

    Is2FAEnabled -->|Yes| Show2FAGate[Navigate to 2FA Gate<br/>Block dashboard access]
    Show2FAGate --> CheckMethod{2FA<br/>Method?}

    CheckMethod -->|TOTP| ShowTOTPInput[Show TOTP Input<br/>"Enter code from app"]
    CheckMethod -->|Email| SendEmailCode[Generate & Send<br/>Email Code]

    ShowTOTPInput --> EnterTOTP[User Enters Code]
    SendEmailCode --> ShowEmailInput[Show Email Input<br/>"Check your email"]
    ShowEmailInput --> EnterEmail[User Enters Code]

    EnterTOTP --> VerifyTOTP[Verify TOTP Code]
    EnterEmail --> VerifyEmail[Verify Email Code<br/>Check expiry]

    VerifyTOTP --> CodeValid{Code<br/>Valid?}
    VerifyEmail --> CodeValid

    CodeValid -->|No| ShowInvalidError[Show "Invalid Code"]
    ShowInvalidError --> CheckMethod

    CodeValid -->|Yes| CreateSession[Create 2FA Session<br/>users/{uid}/twoFactorSessions]
    CreateSession --> SessionDoc["{<br/>  sessionId: uuid,<br/>  verified: true,<br/>  createdAt: timestamp<br/>}"]
    SessionDoc --> Dashboard2[Navigate to Dashboard]
    Dashboard2 --> MonitorSession[Monitor Session<br/>Real-time Listener]

    MonitorSession --> SessionDeleted{Session<br/>Deleted?}
    SessionDeleted -->|Yes| SignOut[Force Sign Out<br/>Return to Login]
    SessionDeleted -->|No| MonitorSession

    SignOut --> End3([End])
    Dashboard2 --> End4([End])

    style FirebaseAuth fill:#4285F4
    style Show2FAGate fill:#EA4335
    style CreateSession fill:#34A853
    style Dashboard fill:#FBBC04
    style Dashboard2 fill:#FBBC04
```

---

## Component and Service Dependencies

### Flutter Widget Hierarchy

```mermaid
graph TB
    subgraph "Root"
        Main[main.dart<br/>MyApp]
    end

    subgraph "Authentication Layer"
        AuthGate[AuthGate<br/>Stream auth state]
        Login[LoginScreen]
        TwoFAGate[TwoFactorGate<br/>Block if 2FA enabled]
        TwoFAVerify[TwoFactorVerificationScreen]
    end

    subgraph "Role-Based Navigation"
        RoleCheck{User Role?}
        CitizenDash[CitizenDashboard]
        DispatcherDash[DispatcherDashboard]
    end

    subgraph "Citizen Screens"
        SOSButton[SOS Button Widget]
        MapView[MapView Widget]
        MedicalForm[MedicalInfoForm]
        Settings[SettingsScreen]
        TwoFASettings[TwoFactorSettingsScreen]
    end

    subgraph "Dispatcher Screens"
        AlertFeed[Emergency Alert Feed<br/>StreamBuilder]
        Analytics[AnalyticsDashboard]
        DispatcherMap[Map with Alert Locations]
    end

    subgraph "Shared Screens"
        CallScreen[CallScreen<br/>WebRTC UI]
        ChatScreen[ChatScreen<br/>Real-time Messages]
        Profile[ProfileScreen]
    end

    Main --> AuthGate
    AuthGate -->|Not logged in| Login
    AuthGate -->|Logged in| TwoFAGate
    TwoFAGate -->|2FA required| TwoFAVerify
    TwoFAGate -->|2FA verified or disabled| RoleCheck

    RoleCheck -->|Citizen| CitizenDash
    RoleCheck -->|Dispatcher| DispatcherDash

    CitizenDash --> SOSButton
    CitizenDash --> MapView
    CitizenDash --> MedicalForm
    CitizenDash --> Settings

    Settings --> TwoFASettings

    DispatcherDash --> AlertFeed
    DispatcherDash --> Analytics
    DispatcherDash --> DispatcherMap

    CitizenDash --> CallScreen
    DispatcherDash --> CallScreen

    CitizenDash --> ChatScreen
    DispatcherDash --> ChatScreen

    CitizenDash --> Profile
    DispatcherDash --> Profile

    style Main fill:#4285F4
    style AuthGate fill:#34A853
    style TwoFAGate fill:#EA4335
    style CitizenDash fill:#FBBC04
    style DispatcherDash fill:#9C27B0
```

### Service Dependencies Graph

```mermaid
graph LR
    subgraph "Core Services"
        Auth[FirebaseAuth]
        Firestore[Cloud Firestore]
        Storage[Firebase Storage]
        FCM[Firebase Cloud<br/>Messaging]
    end

    subgraph "Application Services"
        TwoFactor[TwoFactorService]
        Encryption[EncryptionService]
        MedicalInfo[MedicalInfoService]
        Notification[NotificationService]
        LiveKit[LiveKitService]
        Places[PlacesService]
        Directions[DirectionsService]
        Analytics[AnalyticsService]
        AlertHistory[AlertHistoryService]
    end

    subgraph "External APIs"
        GMapsAPI[Google Maps API]
        PlacesAPI[Google Places API]
        DirectionsAPI[Google Directions API]
        LiveKitAPI[LiveKit Cloud]
        TwilioAPI[Twilio API]
        ResendAPI[Resend API]
    end

    TwoFactor --> Auth
    TwoFactor --> Firestore
    TwoFactor --> FCM

    Encryption --> Auth

    MedicalInfo --> Encryption
    MedicalInfo --> Firestore

    Notification --> FCM
    Notification --> Firestore

    LiveKit --> Firestore
    LiveKit --> LiveKitAPI

    Places --> PlacesAPI
    Places --> Firestore

    Directions --> DirectionsAPI

    Analytics --> Firestore

    AlertHistory --> Firestore

    style TwoFactor fill:#EA4335
    style Encryption fill:#34A853
    style MedicalInfo fill:#4285F4
    style LiveKit fill:#00D4AA
```

---

## Cloud Functions Architecture

### Firebase Cloud Functions Structure

```mermaid
graph TB
    subgraph "Client Requests"
        FlutterApp[Flutter App]
        WebApp[Web App]
    end

    subgraph "Firebase Cloud Functions"
        direction TB

        subgraph "LiveKit Functions"
            GenerateToken[generateLiveKitToken<br/>HTTP Callable]
            TokenLogic[Validate Request<br/>Access Secrets<br/>Generate JWT]
        end

        subgraph "Communication Functions"
            SendEmail[sendEmail<br/>HTTP Callable]
            SendSMS[sendSMS<br/>HTTP Callable]
            EmailLogic[Validate Request<br/>Send via Resend]
            SMSLogic[Validate Request<br/>Send via Twilio]
        end

        subgraph "2FA Functions"
            Verify2FA[verify2FACode<br/>HTTP Callable]
            TwoFALogic[Validate Code<br/>Check Expiry<br/>Update Session]
        end
    end

    subgraph "Secret Manager"
        LiveKitKey[LIVEKIT_API_KEY]
        LiveKitSecret[LIVEKIT_API_SECRET]
    end

    subgraph "Environment Variables"
        TwilioSID[TWILIO_ACCOUNT_SID]
        TwilioToken[TWILIO_AUTH_TOKEN]
        TwilioPhone[TWILIO_PHONE_NUMBER]
        ResendKey[RESEND_API_KEY]
    end

    subgraph "External Services"
        LiveKitCloud[LiveKit Cloud]
        TwilioAPI[Twilio API]
        ResendAPI[Resend API]
    end

    FlutterApp -->|HTTPS| GenerateToken
    WebApp -->|HTTPS| GenerateToken

    FlutterApp -->|HTTPS| SendEmail
    FlutterApp -->|HTTPS| SendSMS
    FlutterApp -->|HTTPS| Verify2FA

    GenerateToken --> TokenLogic
    TokenLogic --> LiveKitKey
    TokenLogic --> LiveKitSecret
    TokenLogic -->|Generate JWT| LiveKitCloud

    SendEmail --> EmailLogic
    EmailLogic --> ResendKey
    EmailLogic -->|API Call| ResendAPI

    SendSMS --> SMSLogic
    SMSLogic --> TwilioSID
    SMSLogic --> TwilioToken
    SMSLogic --> TwilioPhone
    SMSLogic -->|API Call| TwilioAPI

    Verify2FA --> TwoFALogic

    style GenerateToken fill:#00D4AA
    style SendEmail fill:#4285F4
    style SendSMS fill:#34A853
    style LiveKitKey fill:#EA4335
    style LiveKitSecret fill:#EA4335
```

### LiveKit Token Generation Flow

```mermaid
sequenceDiagram
    participant App as Flutter App
    participant CF as Cloud Function<br/>generateLiveKitToken
    participant SM as Firebase Secret<br/>Manager
    participant LK as LiveKit Cloud

    App->>CF: HTTP POST<br/>{alertId, userId}

    CF->>CF: Validate auth token<br/>Check user logged in

    CF->>SM: Access LIVEKIT_API_KEY
    SM-->>CF: Return API Key

    CF->>SM: Access LIVEKIT_API_SECRET
    SM-->>CF: Return API Secret

    CF->>CF: Generate JWT<br/>Room: alert_{alertId}<br/>Identity: user_{userId}<br/>Permissions: publish/subscribe

    Note over CF: JWT Payload:<br/>{<br/>  "sub": user_id,<br/>  "video": {<br/>    "room": "alert_123",<br/>    "roomJoin": true,<br/>    "canPublish": true,<br/>    "canSubscribe": true<br/>  }<br/>}

    CF-->>App: Return token

    App->>LK: Connect with token<br/>WebSocket URL + JWT
    LK->>LK: Validate JWT signature<br/>Check expiry
    LK-->>App: Connection established

    Note over App,LK: WebRTC media streaming
```

---

## SMS/Email Delivery Flow

### Two-Factor Code Delivery

```mermaid
flowchart TB
    Start([User Requests 2FA Code]) --> CheckMethod{Delivery<br/>Method?}

    subgraph "Email Flow"
        direction TB
        Email1[Generate Random<br/>6-digit Code]
        Email2[Store in Firestore<br/>users/{uid}/emailVerification]
        Email3[Call Cloud Function<br/>sendEmail]
        Email4[Cloud Function<br/>Accesses RESEND_API_KEY]
        Email5[Send via Resend API]
        Email6[Resend delivers email]
        Email7[User receives code]

        Email1 --> Email2
        Email2 --> Email3
        Email3 --> Email4
        Email4 --> Email5
        Email5 --> Email6
        Email6 --> Email7
    end

    subgraph "SMS Flow"
        direction TB
        SMS1[Generate Random<br/>6-digit Code]
        SMS2[Store in Firestore<br/>users/{uid}/smsVerification]
        SMS3[Call Cloud Function<br/>sendSMS]
        SMS4[Cloud Function<br/>Accesses Twilio Credentials]
        SMS5[Send via Twilio API]
        SMS6[Twilio delivers SMS]
        SMS7[User receives code]

        SMS1 --> SMS2
        SMS2 --> SMS3
        SMS3 --> SMS4
        SMS4 --> SMS5
        SMS5 --> SMS6
        SMS6 --> SMS7
    end

    CheckMethod -->|Email| Email1
    CheckMethod -->|SMS| SMS1

    Email7 --> Verify[User Enters Code]
    SMS7 --> Verify

    Verify --> Check[Verify Code<br/>Check Expiry]
    Check --> Valid{Valid &<br/>Not Expired?}

    Valid -->|Yes| Success[Verification Successful<br/>Delete Code]
    Valid -->|No| Error[Show Error<br/>Allow Retry]

    Success --> End1([End])
    Error --> End2([End])

    style Email1 fill:#4285F4
    style Email3 fill:#4285F4
    style SMS1 fill:#34A853
    style SMS3 fill:#34A853
    style Success fill:#FBBC04
```

### Email Template Structure

```mermaid
graph TB
    subgraph "Email Composition"
        Subject[Subject: Your Lighthouse<br/>Verification Code]

        subgraph "HTML Body"
            Header[Lighthouse Logo<br/>Emergency Response System]
            Message[You requested a verification<br/>code for 2FA]
            Code[6-Digit Code<br/>Large, Bold Font]
            Expiry[Code expires in 5 minutes]
            Warning[Do not share this code]
            Footer[Lighthouse Team<br/>Contact Info]
        end

        PlainText[Plain Text Fallback<br/>Same content, no HTML]
    end

    subgraph "Resend API Call"
        From[From: noreply@lighthouse.com]
        To[To: user@email.com]
        ReplyTo[Reply-To: support@lighthouse.com]
    end

    Subject --> From
    Header --> From
    Message --> From
    Code --> From
    Expiry --> From
    Warning --> From
    Footer --> From
    PlainText --> From

    From --> SendViaResend[Send via Resend API]
    To --> SendViaResend
    ReplyTo --> SendViaResend

    SendViaResend --> Delivered[Email Delivered]

    style Code fill:#EA4335
    style Expiry fill:#FBBC04
    style Delivered fill:#34A853
```

---

## Complete User Journey

### Citizen Emergency Flow (End-to-End)

```mermaid
flowchart TB
    Start([Citizen Opens App]) --> CheckAuth{Logged<br/>In?}

    CheckAuth -->|No| ShowLogin[Show Login Screen]
    ShowLogin --> EnterCreds[Enter Email + Password]
    EnterCreds --> FirebaseAuth[Firebase Authentication]

    CheckAuth -->|Yes| Check2FA
    FirebaseAuth --> Check2FA{2FA<br/>Enabled?}

    Check2FA -->|Yes| Show2FA[Show 2FA Verification]
    Show2FA --> Enter2FA[Enter TOTP/Email Code]
    Enter2FA --> Verify2FA[Verify Code]
    Verify2FA --> Valid2FA{Valid?}
    Valid2FA -->|No| Show2FA
    Valid2FA -->|Yes| Dashboard

    Check2FA -->|No| Dashboard[Show Citizen Dashboard]

    Dashboard --> ViewMap[View Map with<br/>Current Location]
    ViewMap --> Emergency{Emergency<br/>Situation?}

    Emergency -->|No| BrowseFeatures[Browse Features:<br/>- Medical Info<br/>- Settings<br/>- Facilities]
    BrowseFeatures --> End1([End])

    Emergency -->|Yes| PressSOSButton[Press SOS Button]
    PressSOSButton --> SelectServices[Select Emergency Services<br/>☑ Police<br/>☑ Ambulance<br/>☑ Fire]
    SelectServices --> AddDescription[Add Description<br/>Upload Photos/Videos]
    AddDescription --> ConfirmAlert[Confirm Emergency Alert]

    ConfirmAlert --> CreateAlert[Create Alert in Firestore<br/>Status: pending]
    CreateAlert --> NotifyDispatchers[FCM Notification to<br/>Available Dispatchers]

    NotifyDispatchers --> WaitAcceptance[Wait for Dispatcher<br/>to Accept]

    WaitAcceptance --> AlertAccepted{Dispatcher<br/>Accepts?}

    AlertAccepted -->|Timeout| ShowTimeout[No Dispatcher Available<br/>Try Again or Cancel]
    ShowTimeout --> End2([End])

    AlertAccepted -->|Yes| ShowAccepted[Show "Help is on the way!"<br/>Dispatcher Info<br/>Real-time Location]

    ShowAccepted --> ReceiveCall{Incoming<br/>Call?}

    ReceiveCall -->|Yes| ShowCallDialog[Show Call Dialog<br/>Accept / Decline]
    ShowCallDialog --> AcceptCall{Accept?}
    AcceptCall -->|Yes| JoinCall[Join LiveKit Room<br/>Start Video/Audio]
    AcceptCall -->|No| DeclineCall[Decline Call]

    JoinCall --> InCall[In Call with Dispatcher<br/>- Video/Audio<br/>- Mute/Unmute<br/>- Toggle Camera]
    InCall --> CallEnds{Call<br/>Ends?}
    CallEnds -->|Yes| ReturnToMap

    DeclineCall --> ReturnToMap[Return to Map View<br/>Track Dispatcher Location]
    ReceiveCall -->|No| ReturnToMap

    ReturnToMap --> DispatcherArrives{Dispatcher<br/>Arrives?}
    DispatcherArrives -->|No| ReturnToMap
    DispatcherArrives -->|Yes| ShowArrived[Show "Dispatcher Arrived"<br/>Status: arrived]

    ShowArrived --> Resolution[Emergency Handled<br/>On Site]
    Resolution --> DispatcherResolves[Dispatcher Marks Resolved<br/>Add Resolution Notes]

    DispatcherResolves --> ShowResolved[Show "Emergency Resolved"<br/>Thank You Message]
    ShowResolved --> ViewHistory[View Alert History]
    ViewHistory --> End3([End])

    style PressSOSButton fill:#EA4335
    style CreateAlert fill:#EA4335
    style ShowAccepted fill:#34A853
    style JoinCall fill:#00D4AA
    style ShowResolved fill:#4285F4
```

### Dispatcher Response Flow (End-to-End)

```mermaid
flowchart TB
    Start([Dispatcher Opens App]) --> CheckAuth{Logged<br/>In?}

    CheckAuth -->|No| ShowLogin[Show Login Screen]
    ShowLogin --> Login[Login with Credentials]
    Login --> Dashboard

    CheckAuth -->|Yes| Dashboard[Show Dispatcher Dashboard]

    Dashboard --> MonitorAlerts[Monitor Alert Feed<br/>Real-time StreamBuilder]

    MonitorAlerts --> NewAlert{New Alert<br/>Arrives?}

    NewAlert -->|No| MonitorAlerts
    NewAlert -->|Yes| PushNotif[Receive FCM Push<br/>Notification Sound]

    PushNotif --> ReviewAlert[Review Alert Details:<br/>- Location<br/>- Services Needed<br/>- Description<br/>- Photos/Videos]

    ReviewAlert --> DecideAction{Accept<br/>Alert?}

    DecideAction -->|No| DismissAlert[Dismiss Alert<br/>Continue Monitoring]
    DismissAlert --> MonitorAlerts

    DecideAction -->|Yes| AcceptAlert[Click "Accept Alert"]
    AcceptAlert --> UpdateFirestore[Update Firestore<br/>Status: active<br/>acceptedBy: dispatcher_id]

    UpdateFirestore --> ViewAlertMap[View Alert on Map<br/>Calculate Route<br/>Show Distance/ETA]

    ViewAlertMap --> InitiateCall{Need to<br/>Call Citizen?}

    InitiateCall -->|Yes| StartCall[Click "Call" Button]
    StartCall --> CreateCallDoc[Create Call Document<br/>Status: ringing]
    CreateCallDoc --> RequestToken[Request LiveKit Token<br/>from Cloud Function]
    RequestToken --> JoinRoom[Join LiveKit Room]

    JoinRoom --> WaitAnswer[Wait for Citizen<br/>to Answer]
    WaitAnswer --> Answered{Citizen<br/>Answers?}

    Answered -->|No| MissedCall[Call Declined/Missed<br/>Return to Map]
    Answered -->|Yes| ActiveCall[Active Video/Audio Call<br/>- Assess Situation<br/>- Provide Instructions<br/>- Gather Info]

    ActiveCall --> EndCall[End Call when Done]
    EndCall --> MissedCall

    InitiateCall -->|No| NavigateToSite
    MissedCall --> NavigateToSite[Navigate to Site<br/>Follow Google Maps Route]

    NavigateToSite --> Arrived{Arrived<br/>at Site?}

    Arrived -->|No| UpdateLocation[Update Real-time<br/>Location for Citizen]
    UpdateLocation --> NavigateToSite

    Arrived -->|Yes| MarkArrived[Click "I've Arrived"]
    MarkArrived --> UpdateStatus[Update Firestore<br/>Status: arrived<br/>arrivedAt: timestamp]

    UpdateStatus --> HandleEmergency[Handle Emergency<br/>On Site]

    HandleEmergency --> AccessMedical{Need Medical<br/>Info?}

    AccessMedical -->|Yes| ViewMedical[View Encrypted<br/>Medical Information<br/>- Blood Type<br/>- Allergies<br/>- Medications<br/>- Conditions]
    ViewMedical --> ResolveSituation

    AccessMedical -->|No| ResolveSituation[Resolve Emergency<br/>Situation]

    ResolveSituation --> MarkResolved[Click "Mark as Resolved"]
    MarkResolved --> AddNotes[Add Resolution Notes<br/>Document Actions Taken]

    AddNotes --> UpdateResolved[Update Firestore<br/>Status: resolved<br/>resolvedAt: timestamp<br/>resolutionNotes: text]

    UpdateResolved --> ViewAnalytics[View Analytics<br/>Dashboard Updates]

    ViewAnalytics --> End1([Return to Monitoring])
    End1 --> MonitorAlerts

    style AcceptAlert fill:#34A853
    style StartCall fill:#00D4AA
    style ActiveCall fill:#00D4AA
    style MarkArrived fill:#FBBC04
    style MarkResolved fill:#4285F4
```

---

## Performance and Optimization

### Data Caching Strategy

```mermaid
graph TB
    subgraph "Client App"
        UI[Flutter UI]

        subgraph "Cache Layers"
            Memory[In-Memory Cache<br/>Service-level State]
            LocalDB[Firestore Local<br/>Persistence Cache]
            ServiceWorker[Service Worker Cache<br/>PWA Assets]
        end
    end

    subgraph "Backend"
        Firestore[(Cloud Firestore)]
        Storage[(Firebase Storage)]
        CDN[Firebase CDN]
    end

    UI -->|Read| Memory
    Memory -->|Cache Miss| LocalDB
    LocalDB -->|Cache Miss| Firestore

    UI -->|Assets| ServiceWorker
    ServiceWorker -->|Cache Miss| CDN

    Firestore -->|Real-time Sync| LocalDB
    LocalDB -->|Update| Memory
    Memory -->|Rebuild| UI

    Storage --> CDN

    style Memory fill:#4285F4
    style LocalDB fill:#34A853
    style ServiceWorker fill:#FBBC04
```

### Real-time Update Optimization

```mermaid
flowchart LR
    subgraph "Firestore Updates"
        AlertCreate[Alert Created<br/>in Firestore]
        AlertUpdate[Alert Updated<br/>in Firestore]
    end

    subgraph "Client Listeners"
        Listener1[Citizen App<br/>StreamBuilder<br/>Query: userId == me]
        Listener2[Dispatcher App 1<br/>StreamBuilder<br/>Query: status == pending]
        Listener3[Dispatcher App 2<br/>StreamBuilder<br/>Query: status == pending]
    end

    subgraph "Optimization Techniques"
        IndexedQuery[Composite Index<br/>status + createdAt]
        Pagination[Limit to 20 results<br/>OrderBy timestamp DESC]
        Debounce[Debounced Marker Updates<br/>100ms delay]
    end

    AlertCreate --> IndexedQuery
    AlertUpdate --> IndexedQuery

    IndexedQuery --> Listener1
    IndexedQuery --> Listener2
    IndexedQuery --> Listener3

    Listener1 --> Pagination
    Listener2 --> Pagination
    Listener3 --> Pagination

    Pagination --> Debounce

    Debounce --> UIUpdate[Selective UI Rebuild<br/>Only affected widgets]

    style IndexedQuery fill:#EA4335
    style Pagination fill:#FBBC04
    style Debounce fill:#34A853
```

---

## Security Implementation

### Multi-Layer Security Model

```mermaid
graph TB
    subgraph "Layer 1: Network Security"
        HTTPS[HTTPS/TLS 1.3]
        WSS[WebSocket Secure<br/>wss://]
        SRTP[SRTP Encrypted Media]
    end

    subgraph "Layer 2: Authentication"
        FirebaseAuth[Firebase Auth<br/>Email + Password]
        TwoFA[Two-Factor Auth<br/>TOTP / Email]
        SessionMgmt[Session Management<br/>Real-time Monitoring]
    end

    subgraph "Layer 3: Authorization"
        RBAC[Role-Based Access<br/>Citizen / Dispatcher]
        SecurityRules[Firestore Rules<br/>User-specific Access]
        APIKeys[API Key Restrictions<br/>Domain/App-specific]
    end

    subgraph "Layer 4: Data Protection"
        AES256[AES-256-CBC<br/>Medical Data Encryption]
        KeyDerivation[SHA-256 Key<br/>Derived from UID]
        SecretManager[Firebase Secret Manager<br/>API Credentials]
    end

    subgraph "Layer 5: Input Validation"
        ClientValidation[Client-Side Validators<br/>Email, Phone, Password]
        ServerValidation[Firestore Rules<br/>Schema Validation]
        Sanitization[Input Sanitization<br/>XSS Prevention]
    end

    User[User Device] --> HTTPS
    HTTPS --> FirebaseAuth
    FirebaseAuth --> TwoFA
    TwoFA --> SessionMgmt

    SessionMgmt --> RBAC
    RBAC --> SecurityRules
    SecurityRules --> APIKeys

    APIKeys --> AES256
    AES256 --> KeyDerivation
    KeyDerivation --> SecretManager

    SecretManager --> ClientValidation
    ClientValidation --> ServerValidation
    ServerValidation --> Sanitization

    Sanitization --> DataAccess[(Secure Data Access)]

    WSS --> HTTPS
    SRTP --> WSS

    style HTTPS fill:#4285F4
    style TwoFA fill:#EA4335
    style AES256 fill:#34A853
    style SecurityRules fill:#FBBC04
```

---

## Conclusion

These comprehensive diagrams provide detailed visual documentation of the Lighthouse Emergency Response System's architecture, flows, and implementation details. They complement the main [ARCHITECTURE.md](ARCHITECTURE.md) document and serve as reference material for:

- ✅ **Development**: Understanding system interactions and dependencies
- ✅ **Debugging**: Tracing data flow and identifying bottlenecks
- ✅ **Documentation**: Academic project evaluation and presentation
- ✅ **Onboarding**: Helping new developers understand the system
- ✅ **Security Audits**: Visualizing security layers and data protection

---

**Last Updated:** December 29, 2025
**Version:** 1.0.0
**Created for:** Lighthouse Emergency Response System - Final Year Project
