/**
 * Distance Calculation Helper Functions
 *
 * This module provides geospatial distance calculations using the Haversine formula.
 * I implement these utilities to determine proximity between emergency alerts and
 * dispatchers, enabling location-based dispatcher assignment.
 */

/**
 * Calculates the great-circle distance between two geographic coordinates.
 *
 * I use the Haversine formula to calculate the shortest distance over the earth's
 * surface between two points specified by latitude and longitude. This is essential
 * for determining which dispatchers are within reasonable range to respond to an
 * emergency alert.
 *
 * The calculation accounts for the Earth's curvature and returns distance in kilometers.
 * For dispatcher assignment, I typically filter for dispatchers within 50km of the alert.
 *
 * @param {number} lat1 - Latitude of first point in decimal degrees
 * @param {number} lon1 - Longitude of first point in decimal degrees
 * @param {number} lat2 - Latitude of second point in decimal degrees
 * @param {number} lon2 - Longitude of second point in decimal degrees
 * @returns {number} Distance in kilometers
 */
function calculateDistance(lat1, lon1, lat2, lon2) {
  const R = 6371; // Earth's radius in kilometers
  const dLat = toRadians(lat2 - lat1);
  const dLon = toRadians(lon2 - lon1);

  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRadians(lat1)) *
      Math.cos(toRadians(lat2)) *
      Math.sin(dLon / 2) *
      Math.sin(dLon / 2);

  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  const distance = R * c;

  return distance;
}

/**
 * Converts degrees to radians for trigonometric calculations.
 *
 * I provide this utility function as JavaScript's Math trigonometric functions
 * (sin, cos, etc.) expect radians rather than degrees. This conversion is necessary
 * for the Haversine distance calculation.
 *
 * @param {number} degrees - Angle in degrees
 * @returns {number} Angle in radians
 */
function toRadians(degrees) {
  return degrees * (Math.PI / 180);
}

module.exports = {
  calculateDistance,
  toRadians,
};
