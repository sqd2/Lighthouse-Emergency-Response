/**
 * User Helper Functions
 *
 * This module provides utility functions for retrieving and formatting user information
 * from Firestore. I implement safe error handling to ensure graceful degradation when
 * user data is unavailable or incomplete.
 */

const admin = require("firebase-admin");

/**
 * Retrieves the display name for a user from their Firestore profile.
 *
 * I query the user's document and return their name field if available, falling back
 * to their email address if name is not set. If the user document doesn't exist or
 * an error occurs, I return "Unknown User" to prevent display issues.
 *
 * @param {string} userId - The Firebase Auth UID of the user
 * @returns {Promise<string>} User's display name, email, or "Unknown User"
 */
async function getUserName(userId) {
  try {
    const userDoc = await admin.firestore().collection("users").doc(userId).get();
    if (!userDoc.exists) {
      return "Unknown User";
    }
    const userData = userDoc.data();
    return userData.name || userData.email || "Unknown User";
  } catch (error) {
    console.error(`[ERROR] Error fetching user name for ${userId}:`, error);
    return "Unknown User";
  }
}

/**
 * Formats user display as "Name (email)" for clear identification.
 *
 * I provide a consistent format for displaying user information throughout the
 * application. If the name and email are identical or either is missing, I return
 * just the available identifier to avoid redundant display like "user@example.com (user@example.com)".
 *
 * @param {string} name - User's display name
 * @param {string} email - User's email address
 * @returns {string} Formatted user display string
 */
function formatUserDisplay(name, email) {
  if (!name || !email || name === email) {
    return name || email || "Unknown User";
  }
  return `${name} (${email})`;
}

module.exports = {
  getUserName,
  formatUserDisplay,
};
