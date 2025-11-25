@echo off
echo Building Lighthouse for Web...
echo.
echo Installing dependencies...
flutter pub get
echo.
echo Starting web server...
echo If you see errors, check the console output below.
echo.
flutter run -d chrome --web-renderer html
