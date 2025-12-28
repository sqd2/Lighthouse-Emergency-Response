/**
 * SOS Emergency Alert Trigger Functions
 *
 * This module contains Firestore-triggered Cloud Functions that respond to emergency
 * alert lifecycle events. I implement comprehensive notification workflows for both
 * citizens requesting help and dispatchers responding to emergencies, while also
 * keeping emergency contacts informed of alert status changes.
 *
 * Trigger Flow:
 * 1. onSOSCreated: Citizen creates alert → Notify all active dispatchers + emergency contact
 * 2. onSOSAccepted: Dispatcher accepts → Notify citizen + emergency contact
 * 3. onDispatcherArrived: Dispatcher arrives → Notify citizen + emergency contact
 * 4. onSOSCancelled: Citizen cancels → Notify dispatcher + emergency contact
 * 5. onSOSResolved: Dispatcher resolves → Notify citizen + emergency contact
 */

const {onDocumentCreated, onDocumentUpdated} = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
const {getUserName, formatUserDisplay} = require("../helpers/user-helpers");
const {sendNotificationToUser} = require("../helpers/notification-helpers");
const {calculateDistance} = require("../helpers/distance-helpers");
const {notifyEmergencyContact} = require("../helpers/emergency-contact");

/**
 * Triggered when a new SOS emergency alert is created.
 *
 * This function performs comprehensive dispatcher notification based on proximity and
 * availability. I calculate the distance between each active dispatcher and the emergency
 * location, then notify ALL active dispatchers regardless of distance. This ensures
 * maximum response coverage for emergencies.
 *
 * Additionally, I notify the citizen's emergency contact with the alert details and
 * location, providing family/friends with immediate awareness of the situation.
 *
 * Notification Recipients:
 * - All active dispatchers (with distance information)
 * - Citizen's emergency contact (via SMS/email)
 */
exports.onSOSCreated = onDocumentCreated("emergency_alerts/{alertId}", async (event) => {
  const alertData = event.data.data();
  const alertId = event.params.alertId;

  console.log(`[ALERT] New SOS created: ${alertId} from ${alertData.userEmail}`);

  // Get citizen's name for notifications
  const citizenName = await getUserName(alertData.userId);
  const citizenDisplay = formatUserDisplay(citizenName, alertData.userEmail);

  // Extract lat/lon from GeoPoint or separate fields (backward compatibility)
  let alertLat, alertLon;
  if (alertData.location) {
    // New format: GeoPoint in location field
    alertLat = alertData.location.latitude;
    alertLon = alertData.location.longitude;
  } else if (alertData.lat && alertData.lon) {
    // Old format: separate lat/lon fields
    alertLat = alertData.lat;
    alertLon = alertData.lon;
  }

  console.log(`[LOCATION] Alert location: ${alertLat}, ${alertLon}`);

  // Validate alert location data
  if (!alertLat || !alertLon || isNaN(alertLat) || isNaN(alertLon)) {
    console.error(`[ERROR] Invalid alert location data: lat=${alertLat}, lon=${alertLon}`);
    return;
  }

  try {
    // Get all active dispatchers
    console.log("[SEARCH] Searching for active dispatchers...");
    const dispatchersSnapshot = await admin.firestore()
        .collection("users")
        .where("role", "==", "dispatcher")
        .where("isActive", "==", true)
        .get();

    console.log(`[DATA] Found ${dispatchersSnapshot.size} active dispatcher(s)`);

    if (dispatchersSnapshot.empty) {
      console.log("[ERROR] No active dispatchers found");
      return;
    }

    // Calculate distance for each dispatcher
    const dispatchersWithDistance = [];

    dispatchersSnapshot.docs.forEach((doc) => {
      const data = doc.data();
      const dispatcherId = doc.id;

      // Check if dispatcher has location data
      if (data.lastKnownLocation) {
        const dispatcherLat = data.lastKnownLocation.latitude;
        const dispatcherLon = data.lastKnownLocation.longitude;

        // Validate dispatcher location
        if (isNaN(dispatcherLat) || isNaN(dispatcherLon)) {
          console.log(`[WARN] Dispatcher ${data.email} has invalid location: lat=${dispatcherLat}, lon=${dispatcherLon} - skipping`);
          return;
        }

        // Calculate distance from dispatcher to alert
        const distance = calculateDistance(
            dispatcherLat,
            dispatcherLon,
            alertLat,
            alertLon,
        );

        // Validate calculated distance
        if (isNaN(distance)) {
          console.error(`[ERROR] Distance calculation returned NaN for dispatcher ${data.email}`);
          console.error(`   Dispatcher: lat=${dispatcherLat}, lon=${dispatcherLon}`);
          console.error(`   Alert: lat=${alertLat}, lon=${alertLon}`);
          return;
        }

        dispatchersWithDistance.push({
          id: dispatcherId,
          email: data.email,
          distance: distance,
          hasToken: !!(data.fcmToken || (data.fcmTokens && data.fcmTokens.length > 0)),
        });

        console.log(`[USER] Dispatcher: ${data.email}, Distance: ${distance.toFixed(2)} km`);
      } else {
        console.log(`[WARN] Dispatcher ${data.email} has no location data - skipping`);
      }
    });

    if (dispatchersWithDistance.length === 0) {
      console.log("[ERROR] No dispatchers with location data found");
      return;
    }

    // Sort by distance (nearest first) - for logging purposes
    dispatchersWithDistance.sort((a, b) => a.distance - b.distance);

    // Notify ALL dispatchers (no distance limitation)
    console.log(`[LOCATION] Notifying ALL ${dispatchersWithDistance.length} active dispatcher(s):`);
    dispatchersWithDistance.forEach((d, index) => {
      console.log(`  ${index + 1}. ${d.email} - ${d.distance.toFixed(2)} km away`);
    });

    // Send notification to ALL active dispatchers
    const notificationPromises = dispatchersWithDistance.map((dispatcher) => {
      const distanceText = dispatcher.distance < 1 ?
        `${(dispatcher.distance * 1000).toFixed(0)} m` :
        `${dispatcher.distance.toFixed(1)} km`;

      return sendNotificationToUser(
          dispatcher.id,
          "[ALERT] New Emergency Alert",
          `Emergency SOS from ${citizenDisplay} - ${distanceText} away`,
          {
            type: "new_sos",
            alertId: alertId,
            distance: String(dispatcher.distance.toFixed(2)),
            distanceText: distanceText,
          },
      );
    });

    await Promise.all(notificationPromises);
    console.log(`[SUCCESS] Notified ${dispatchersWithDistance.length} dispatcher(s) - ALL active dispatchers notified`);

    // Notify emergency contact
    console.log("[EMERGENCY_CONTACT] Attempting to notify emergency contact for user:", alertData.userId);
    try {
      const locationUrl = `https://www.google.com/maps?q=${alertLat},${alertLon}`;
      const emergencyMessage = `EMERGENCY ALERT: ${citizenName || alertData.userEmail} has initiated an SOS.\n\nDescription: ${alertData.description || "No description provided"}\n\nLocation: ${locationUrl}\n\nStatus: Emergency services have been notified.`;

      await notifyEmergencyContact(
          alertData.userId,
          citizenName,
          alertData.userEmail,
          emergencyMessage,
          "[URGENT] Emergency SOS Initiated",
      );
      console.log("[EMERGENCY_CONTACT] Emergency contact notification process completed");
    } catch (emergencyContactError) {
      console.error("[EMERGENCY_CONTACT] Failed to notify emergency contact:", emergencyContactError);
    }
  } catch (error) {
    console.error("[ERROR] Error in onSOSCreated:", error);
  }
});

/**
 * Triggered when an SOS alert status changes from pending to active.
 *
 * This occurs when a dispatcher accepts an emergency alert. I notify the citizen
 * that help is on the way, providing them with the dispatcher's identification.
 * I also update the emergency contact to inform them that the alert has been
 * accepted and response is in progress.
 *
 * Notification Recipients:
 * - Citizen who created the alert
 * - Citizen's emergency contact
 */
exports.onSOSAccepted = onDocumentUpdated("emergency_alerts/{alertId}", async (event) => {
  const beforeData = event.data.before.data();
  const afterData = event.data.after.data();
  const alertId = event.params.alertId;

  // Check if dispatcher just accepted (status: pending → active)
  const wasPending = beforeData.status === "pending";
  const nowActive = afterData.status === "active";
  const hasDispatcher = afterData.acceptedBy && !beforeData.acceptedBy;

  if (wasPending && nowActive && hasDispatcher) {
    console.log(`[SUCCESS] SOS ${alertId} accepted by ${afterData.acceptedByEmail}`);

    try {
      const citizenId = afterData.userId;

      // Get dispatcher's name for notification
      const dispatcherName = await getUserName(afterData.acceptedBy);
      const dispatcherDisplay = formatUserDisplay(dispatcherName, afterData.acceptedByEmail);

      await sendNotificationToUser(
          citizenId,
          "[SUCCESS] Help is on the way!",
          `Dispatcher ${dispatcherDisplay} has accepted your emergency request`,
          {
            type: "sos_accepted",
            alertId: alertId,
            dispatcherEmail: afterData.acceptedByEmail,
          },
      );

      console.log(`[DEVICE] Notified citizen ${citizenId} of SOS acceptance`);

      // Notify emergency contact
      const citizenName = await getUserName(afterData.userId);
      const updateMessage = `SOS UPDATE: A dispatcher (${dispatcherDisplay}) has accepted the emergency alert from ${citizenName || afterData.userEmail}.\n\nStatus: Help is on the way!\n\nAlert ID: ${alertId}`;

      await notifyEmergencyContact(
          afterData.userId,
          citizenName,
          afterData.userEmail,
          updateMessage,
          "[UPDATE] Emergency Help Accepted",
      );
    } catch (error) {
      console.error("[ERROR] Error in onSOSAccepted:", error);
    }
  }
});

/**
 * Triggered when an SOS alert status changes from active to arrived.
 *
 * This occurs when a dispatcher marks themselves as having arrived at the
 * emergency scene. I notify the citizen that help has arrived, providing
 * reassurance and the dispatcher's identification. I also update the emergency
 * contact with this positive status change.
 *
 * Notification Recipients:
 * - Citizen at the emergency location
 * - Citizen's emergency contact
 */
exports.onDispatcherArrived = onDocumentUpdated("emergency_alerts/{alertId}", async (event) => {
  const beforeData = event.data.before.data();
  const afterData = event.data.after.data();
  const alertId = event.params.alertId;

  // Check if status changed to 'arrived'
  const statusChanged = beforeData.status === "active" && afterData.status === "arrived";

  if (statusChanged) {
    console.log(`[TARGET] Dispatcher arrived at alert ${alertId}`);

    try {
      const citizenId = afterData.userId;
      const dispatcherEmail = afterData.acceptedByEmail || "Dispatcher";

      // Get dispatcher's name for notification
      const dispatcherName = afterData.acceptedBy ? await getUserName(afterData.acceptedBy) : dispatcherEmail;
      const dispatcherDisplay = formatUserDisplay(dispatcherName, dispatcherEmail);

      await sendNotificationToUser(
          citizenId,
          "[ALERT] Dispatcher Arrived",
          `${dispatcherDisplay} has arrived at your location`,
          {
            type: "dispatcher_arrived",
            alertId: alertId,
            dispatcherEmail: dispatcherEmail,
          },
      );

      console.log(`[DEVICE] Notified citizen ${citizenId} of dispatcher arrival`);

      // Notify emergency contact
      const citizenName = await getUserName(afterData.userId);
      const updateMessage = `SOS UPDATE: Dispatcher (${dispatcherDisplay}) has arrived at the emergency location for ${citizenName || afterData.userEmail}.\n\nStatus: Help has arrived!\n\nAlert ID: ${alertId}`;

      await notifyEmergencyContact(
          afterData.userId,
          citizenName,
          afterData.userEmail,
          updateMessage,
          "[UPDATE] Emergency Help Arrived",
      );
    } catch (error) {
      console.error("[ERROR] Error in onDispatcherArrived:", error);
    }
  }
});

/**
 * Triggered when a citizen cancels their SOS alert.
 *
 * This can occur at any point in the emergency workflow when the citizen
 * determines help is no longer needed. I notify the assigned dispatcher (if any)
 * that the alert has been cancelled, along with the cancellation reason. I also
 * inform the emergency contact that the situation has been resolved.
 *
 * Notification Recipients:
 * - Assigned dispatcher (if alert was accepted)
 * - Citizen's emergency contact
 */
exports.onSOSCancelled = onDocumentUpdated("emergency_alerts/{alertId}", async (event) => {
  const beforeData = event.data.before.data();
  const afterData = event.data.after.data();
  const alertId = event.params.alertId;

  // Check if status changed to 'cancelled'
  const wasCancelled = afterData.status === "cancelled" && beforeData.status !== "cancelled";

  if (wasCancelled) {
    console.log(`[ERROR] SOS ${alertId} cancelled by citizen`);

    try {
      const dispatcherId = afterData.acceptedBy;
      const citizenEmail = afterData.userEmail || "Citizen";
      const cancellationReason = afterData.cancellationReason || "No reason provided";

      // Only notify if a dispatcher had accepted
      if (dispatcherId) {
        // Get citizen's name for notification
        const citizenName = await getUserName(afterData.userId);
        const citizenDisplay = formatUserDisplay(citizenName, citizenEmail);

        await sendNotificationToUser(
            dispatcherId,
            "[WARN] Alert Cancelled",
            `${citizenDisplay} cancelled their emergency alert. Reason: ${cancellationReason}`,
            {
              type: "sos_cancelled",
              alertId: alertId,
              citizenEmail: citizenEmail,
              reason: cancellationReason,
            },
        );

        console.log(`[DEVICE] Notified dispatcher ${dispatcherId} of cancellation`);
      }

      // Notify emergency contact
      const citizenName = await getUserName(afterData.userId);
      const updateMessage = `SOS UPDATE: The emergency alert from ${citizenName || citizenEmail} has been CANCELLED.\n\nReason: ${cancellationReason}\n\nStatus: Alert resolved - No longer active.\n\nAlert ID: ${alertId}`;

      await notifyEmergencyContact(
          afterData.userId,
          citizenName,
          citizenEmail,
          updateMessage,
          "[RESOLVED] Emergency Cancelled",
      );
    } catch (error) {
      console.error("[ERROR] Error in onSOSCancelled:", error);
    }
  }
});

/**
 * Triggered when a dispatcher marks an SOS alert as resolved.
 *
 * This represents the successful conclusion of an emergency response. I notify
 * the citizen that their emergency has been officially resolved by the dispatcher,
 * providing closure to the incident. I also inform the emergency contact that
 * the situation has been successfully handled.
 *
 * Notification Recipients:
 * - Citizen who created the alert
 * - Citizen's emergency contact
 */
exports.onSOSResolved = onDocumentUpdated("emergency_alerts/{alertId}", async (event) => {
  const beforeData = event.data.before.data();
  const afterData = event.data.after.data();
  const alertId = event.params.alertId;

  // Check if status changed to 'resolved'
  const wasResolved = afterData.status === "resolved" && beforeData.status !== "resolved";

  if (wasResolved) {
    console.log(`[SUCCESS] SOS ${alertId} marked as resolved`);

    try {
      const citizenId = afterData.userId;
      const dispatcherEmail = afterData.acceptedByEmail || "Dispatcher";

      // Get dispatcher's name for notification
      const dispatcherName = afterData.acceptedBy ? await getUserName(afterData.acceptedBy) : dispatcherEmail;
      const dispatcherDisplay = formatUserDisplay(dispatcherName, dispatcherEmail);

      await sendNotificationToUser(
          citizenId,
          "[SUCCESS] Emergency Resolved",
          `${dispatcherDisplay} has marked your emergency as resolved`,
          {
            type: "sos_resolved",
            alertId: alertId,
            dispatcherEmail: dispatcherEmail,
          },
      );

      console.log(`[DEVICE] Notified citizen ${citizenId} of resolution`);

      // Notify emergency contact
      const citizenName = await getUserName(afterData.userId);
      const updateMessage = `SOS UPDATE: The emergency alert from ${citizenName || afterData.userEmail} has been RESOLVED.\n\nDispatcher: ${dispatcherDisplay}\n\nStatus: Emergency successfully handled - All clear!\n\nAlert ID: ${alertId}`;

      await notifyEmergencyContact(
          afterData.userId,
          citizenName,
          afterData.userEmail,
          updateMessage,
          "[RESOLVED] Emergency Completed",
      );
    } catch (error) {
      console.error("[ERROR] Error in onSOSResolved:", error);
    }
  }
});
