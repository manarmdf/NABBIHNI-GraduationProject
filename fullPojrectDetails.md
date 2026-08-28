# Nabbihni - Full Project Details

This document provides a comprehensive overview of the Nabbihni project, detailing the architecture, technology stack, libraries, machine learning models, and core logic. It is designed to serve as the foundation for a full project report or Word document.

---

## 1. Project Overview
**Nabbihni** is a smart, AI-powered reminder application built with Flutter. It goes far beyond simple time-based alarms by integrating location-based triggers, Natural Language Processing (NLP), Optical Character Recognition (OCR) for handwritten notes, and a custom Machine Learning (ML) model that predicts user habits to suggest reminder categories and locations. The application is fully bilingual, seamlessly supporting both English and Arabic.

---

## 2. Technology Stack & Architecture

### Frontend (Mobile App)
- **Framework**: Flutter (Dart)
- **UI/UX**: Modern Material Design 3, customized with a premium aesthetic featuring soft colors, rounded corners, dynamic chips, and micro-animations.

### Backend & Database (BaaS)
- **Platform**: Firebase
- **Authentication**: Firebase Auth for secure user registration and login.
- **Database**: Cloud Firestore (NoSQL) for real-time syncing of user profiles, saved locations, and reminder data across devices.

### Artificial Intelligence & Machine Learning
- **Habit Prediction**: TensorFlow Lite (`.tflite`). A custom, on-device ML model that learns from time and text to predict categories and locations.
- **Vision / OCR**: Ollama API. Integrates with advanced cloud/local vision models to extract text from handwritten notes.

---

## 3. Core Libraries (Dependencies)
The project relies on the following key Flutter packages:

- **`cloud_firestore` & `firebase_auth`**: Core backend connectivity and user management.
- **`tflite_flutter`**: Executes the local TensorFlow Lite model for habit prediction without requiring internet access.
- **`speech_to_text`**: Captures user voice input for quick, hands-free reminder creation in both English and Arabic.
- **`flutter_tts`**: Text-to-Speech engine used to read reminder titles aloud to the user.
- **`flutter_local_notifications` & `timezone`**: Handles the scheduling, triggering, and background actions (like Snoozing) of on-device alerts.
- **`geolocator`**: Fetches the device's real-time GPS coordinates for location-aware features.
- **`http`**: Manages REST API calls, specifically for communicating with the Ollama OCR endpoint.
- **`image_picker`**: Allows users to snap photos of handwritten notes directly from the camera.
- **`intl`**: Formats dates and times beautifully in the UI.

---

## 4. Detailed System Components & Functions

### A. Database Structure (Firestore)
Data is securely scoped per user:
- `users/{uid}/` -> **User Document**: Stores profile info like name and `nearby_radius_meters`.
  - `locations/{docId}` -> **Subcollection**: User's custom saved places (Home, Work, Gym, School) with exact lat/lng.
  - `reminders/{reminderId}` -> **Subcollection**: The core reminder records.
    - **Fields**: `id`, `title`, `dateTime` (ISO8601 string), `category`, `locationType`, `lat`, `lng`, `address`, `priority`, `isCompleted`, `snoozeDurationMinutes`, `createdAt` (Server Timestamp).

### B. Natural Language Processing (NLP) - `text_parser.dart`
The `parseReminderText()` function takes raw text input (typed, spoken, or scanned) and extracts actionable structured data.
- **Bilingual Regex**: Uses advanced regular expressions to detect dates (e.g., "next monday", "بكرة"), times (e.g., "5pm", "الساعة ٥"), and relative terms (e.g., "اليوم").
- **Digit Normalization**: Automatically converts Eastern Arabic numerals (٠١٢٣٤٥٦٧٨٩) to Western digits (0123456789) to ensure unified parsing.
- **Keyword Mapping & Heuristics**: Auto-detects place types (e.g., "milk" -> "grocery") and categories (e.g., "meeting" -> "work") using an extensive English/Arabic keyword dictionary.

### C. AI Habit Prediction Model - `habit_helper.dart`
A TensorFlow Lite model that learns user patterns to make creating reminders faster.
- **Dual-Head Architecture**: A shared MLP (Multi-Layer Perceptron) trunk (128 -> 64 nodes) that splits into two outputs:
  1. `Category` Head: Predicts if the task is personal, work, family, or other.
  2. `Location Type` Head: Predicts if the task requires a pharmacy, grocery, gym, etc.
- **Feature Encoding**: Inputs consist of cyclic time data (sine/cosine of the day of the week and hour of the day) and a binary keyword vector derived from the reminder title using a built-in stemming and synonym system.
- **Personalized Blending (`predictPersonalized`)**: A highly advanced function that combines the global TFLite model's predictions with the user's actual historical data from Firestore using Kernel-Density Estimation. It smoothly transitions from global AI suggestions to fully personalized suggestions as the user creates more reminders.

### D. Optical Character Recognition (OCR) - `ocr_helper.dart`
Allows users to create reminders simply by taking a picture of a handwritten sticky note.
- Takes an image via `image_picker`, encodes it to Base64, and sends it to the Ollama endpoint via an HTTP POST request.
- Uses a highly specific system prompt instructing the vision model to read both English and Arabic, ignore crossed-out words, fix spelling mistakes caused by bad handwriting, and return only the clean, final text.

### E. Location & Geofencing Services
- **`osm_place_service.dart`**: Interfaces with OpenStreetMap (Overpass API) to dynamically find generic places (e.g., pharmacies, grocery stores, banks) near the user's current GPS coordinates.
- **`nearby_banner.dart`**: Continuously checks the user's location against their active reminders. If a user has a reminder to "Buy medicine" (LocationType: Pharmacy) and walks near a pharmacy, a dynamic banner appears at the top of the screen showing the distance and offering a quick link to open Google Maps.

### F. Scheduling & Notifications - `notifications.dart`
- Uses `FlutterLocalNotificationsPlugin` to schedule precise alarms.
- Implements background isolates so users can click a "Snooze for 15 minutes" button directly from their phone's lock screen or notification tray, which automatically updates the database and reschedules the alarm without opening the app.

---

## 5. UI / UX Design & Workflows

### Main Screens
- **`RemindersScreen`**: The central hub. Features real-time Firestore synchronization, horizontal filtering chips (Active, Completed, Priority, Category), and groups reminders dynamically (Today, Tomorrow, Upcoming, Uncompleted). Contains Floating Action Buttons for quick Voice Input and standard addition.
- **`AddReminderSheet`**: A comprehensive, scrollable bottom sheet for creating/editing reminders. 
  - **Inputs**: Supports standard text typing, a Microphone button for voice transcription, and a Scanner button for OCR.
  - **Dynamic AI**: As the user types or speaks, `SuggestionChips` instantly appear, offering AI predictions for the category and time (e.g., "Work · 92%").
- **`ProfileScreen`**: Allows users to manage their account, edit their display name, set up personal locations, and adjust the GPS detection radius using a slider.

### Design System
Managed in `constants.dart` and `app_theme.dart`. The app avoids generic colors in favor of a highly curated palette:
- **Primary**: Soft Blue (`#8BB2CD`)
- **Accent**: Coral (`#F28C84`)
- **Success**: Emerald (`#10B981`)
- **Background**: Light Fog (`#E1ECF4`)
The design heavily utilizes `AnimatedContainer`, soft shadows, and glass-like borders to create an interface that feels responsive, alive, and premium.
