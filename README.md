# sensor_calibration

## Files
- `index.html`: student mobile submission page (name, slope `m`, intercept `b`) with submit/resubmit flow.
- `view.html`: live classroom page with QR code to root URL and realtime submissions table.
- `firebase-config.js`: editable Firebase config template.
- `matlab/calibration_leaderboard.m`: polls Firebase every 5 seconds, ranks SSE, and plots top 5 lines.

## Firebase setup
1. Edit `firebase-config.js` and paste your project values.
2. In Firebase Realtime Database, enable read/write for your class use.
3. Host these files on Firebase Hosting (or any static host) with `index.html` at root.

## MATLAB setup
1. Open `matlab/calibration_leaderboard.m`.
2. Replace `firebaseBaseUrl` with your actual realtime database URL.
3. Run the script. It will:
   - Plot fixed calibration data points as thick `x` markers.
   - Poll `submissions.json` every 5 seconds.
   - Print student SSE ranking in the MATLAB console.
   - Replot top 5 student lines and legend entries like `Allan - 10.2`.
