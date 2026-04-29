# App Icon Setup Guide

## Final App Name
**"Web APP"**

---

## Icon Requirements

### Android Icons
Place your app icon files in the following directories:

- `android/app/src/main/res/mipmap-mdpi/ic_launcher.png` (48x48 px)
- `android/app/src/main/res/mipmap-hdpi/ic_launcher.png` (72x72 px)
- `android/app/src/main/res/mipmap-xhdpi/ic_launcher.png` (96x96 px)
- `android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png` (144x144 px)
- `android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png` (192x192 px)

**Recommended Icon Design:**
- Square icon with rounded corners (Android will apply adaptive icon mask)
- 1024x1024 px source image recommended
- Transparent background or solid color
- QR code symbol or web browser icon would be appropriate

### iOS Icons
Place your app icon files in:
`ios/Runner/Assets.xcassets/AppIcon.appiconset/`

**Required Sizes:**
- 20x20 pt (@2x = 40x40, @3x = 60x60)
- 29x29 pt (@2x = 58x58, @3x = 87x87)
- 40x40 pt (@2x = 80x80, @3x = 120x120)
- 60x60 pt (@2x = 120x120, @3x = 180x180)
- 1024x1024 pt (App Store icon)

### Web Icons
Place your app icon files in:
`web/icons/`

**Required Sizes:**
- `Icon-192.png` (192x192 px)
- `Icon-512.png` (512x512 px)
- `Icon-maskable-192.png` (192x192 px, maskable)
- `Icon-maskable-512.png` (512x512 px, maskable)

---

## Quick Setup Using Flutter Launcher Icons

### Option 1: Using flutter_launcher_icons Package (Recommended)

1. Add to `pubspec.yaml`:
```yaml
dev_dependencies:
  flutter_launcher_icons: ^0.13.1

flutter_launcher_icons:
  android: true
  ios: true
  web: true
  image_path: "assets/icon/app_icon.png"  # Your 1024x1024 icon
  adaptive_icon_background: "#FFFFFF"  # Background color
  adaptive_icon_foreground: "assets/icon/app_icon_foreground.png"
```

2. Create your icon (1024x1024 px) and place it at `assets/icon/app_icon.png`

3. Run:
```bash
flutter pub get
flutter pub run flutter_launcher_icons
```

### Option 2: Manual Setup

1. Create a 1024x1024 px icon with your design
2. Use an online tool like:
   - https://www.appicon.co/
   - https://icon.kitchen/
   - https://www.favicon-generator.org/
3. Generate all required sizes
4. Replace the existing icon files in the directories mentioned above

---

## Icon Design Suggestions

**Theme Ideas:**
- QR code scanner symbol
- Web browser icon
- Combination of QR code + browser
- Modern, minimalist design
- Brand colors matching your theme

**Best Practices:**
- Keep it simple and recognizable at small sizes
- Use high contrast colors
- Avoid text in the icon
- Test at different sizes to ensure clarity

---

## Current Icon Locations

### Android
- `/android/app/src/main/res/mipmap-*/ic_launcher.png`

### iOS  
- `/ios/Runner/Assets.xcassets/AppIcon.appiconset/`

### Web
- `/web/icons/Icon-*.png`

