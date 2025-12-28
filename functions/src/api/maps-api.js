/**
 * Maps API Module
 *
 * I provide proxy endpoints for Google Maps APIs (Places and Directions).
 * These functions prevent CORS issues when calling Google APIs from web browsers.
 *
 * Functions:
 * - searchNearbyPlaces: Searches for nearby places using Google Places API
 * - getDirections: Gets directions between two points using Google Directions API
 */

const {onRequest} = require("firebase-functions/v2/https");
const cors = require("cors")({origin: true});

const GOOGLE_API_KEY = "GOOGLE_MAPS_API_KEY";

/**
 * Cloud Function to proxy Google Places API requests
 * This avoids CORS issues when calling from web browsers
 */
exports.searchNearbyPlaces = onRequest((request, response) => {
  cors(request, response, async () => {
    try {
      // Only allow POST requests
      if (request.method !== "POST") {
        response.status(405).send("Method Not Allowed");
        return;
      }

      const {latitude, longitude, radius, type} = request.body;

      // Validate input
      if (!latitude || !longitude || !radius || !type) {
        response.status(400).json({
          error: "Missing required parameters: latitude, longitude, radius, type",
        });
        return;
      }

      // Build Google Places API URL
      const url = `https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=${latitude},${longitude}&radius=${radius}&type=${type}&key=${GOOGLE_API_KEY}`;

      // Fetch from Google Places API
      const apiResponse = await fetch(url);
      const data = await apiResponse.json();

      if (data.status === "REQUEST_DENIED") {
        response.status(403).json({
          error: "API Key Error",
          message: data.error_message,
        });
        return;
      }

      // Return the results
      response.status(200).json({
        status: data.status,
        results: data.results || [],
      });
    } catch (error) {
      console.error("Error fetching places:", error);
      response.status(500).json({
        error: "Internal Server Error",
        message: error.message,
      });
    }
  });
});

/**
 * Cloud Function to proxy Google Directions API requests
 * This avoids CORS issues when calling from web browsers
 */
exports.getDirections = onRequest((request, response) => {
  cors(request, response, async () => {
    try {
      // Only allow POST requests
      if (request.method !== "POST") {
        response.status(405).send("Method Not Allowed");
        return;
      }

      const {originLat, originLng, destLat, destLng} = request.body;

      // Validate input
      if (!originLat || !originLng || !destLat || !destLng) {
        response.status(400).json({
          error: "Missing required parameters",
        });
        return;
      }

      // Build Google Directions API URL
      const url = `https://maps.googleapis.com/maps/api/directions/json?origin=${originLat},${originLng}&destination=${destLat},${destLng}&key=${GOOGLE_API_KEY}`;

      // Fetch from Google Directions API
      const apiResponse = await fetch(url);
      const data = await apiResponse.json();

      if (data.status === "REQUEST_DENIED") {
        response.status(403).json({
          error: "API Key Error",
          message: data.error_message,
        });
        return;
      }

      // Return the results
      response.status(200).json(data);
    } catch (error) {
      console.error("Error fetching directions:", error);
      response.status(500).json({
        error: "Internal Server Error",
        message: error.message,
      });
    }
  });
});
