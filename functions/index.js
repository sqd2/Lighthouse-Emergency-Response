const admin = require("firebase-admin");

// Initialize Firebase Admin SDK
admin.initializeApp();

// Import trigger modules
const sosTriggersModule = require("./src/triggers/sos-triggers");
const communicationTriggersModule = require("./src/triggers/communication-triggers");

// Import API modules
const mapsApiModule = require("./src/api/maps-api");
const notificationsApiModule = require("./src/api/notifications-api");
const livekitApiModule = require("./src/api/livekit-api");
const communicationsApiModule = require("./src/api/communications-api");
const adminApiModule = require("./src/api/admin-api");

// Export Maps API functions
exports.searchNearbyPlaces = mapsApiModule.searchNearbyPlaces;
exports.getDirections = mapsApiModule.getDirections;

// Export Notifications API functions
exports.testNotification = notificationsApiModule.testNotification;
exports.sendEmergencyContactSMS = notificationsApiModule.sendEmergencyContactSMS;

// Export LiveKit API functions
exports.generateLiveKitToken = livekitApiModule.generateLiveKitToken;

// Export Communications API functions
exports.sendEmail = communicationsApiModule.sendEmail;
exports.sendSMS = communicationsApiModule.sendSMS;

// Export Admin API functions
exports.deleteAllFacilities = adminApiModule.deleteAllFacilities;

// Export SOS trigger functions
exports.onSOSCreated = sosTriggersModule.onSOSCreated;
exports.onSOSAccepted = sosTriggersModule.onSOSAccepted;
exports.onDispatcherArrived = sosTriggersModule.onDispatcherArrived;
exports.onSOSCancelled = sosTriggersModule.onSOSCancelled;
exports.onSOSResolved = sosTriggersModule.onSOSResolved;

// Export communication trigger functions
exports.onMessageSent = communicationTriggersModule.onMessageSent;
exports.onCallCreated = communicationTriggersModule.onCallCreated;