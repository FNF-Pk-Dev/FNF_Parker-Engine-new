# Android 16 Predictive Back Gesture Support

For Android 13+ (API 33+) and Android 16, predictive back gestures don't generate KEY events. This project now includes a custom `GameActivity.java` with `OnBackInvokedCallback` support.

## Files Modified

### 1. Project.xml
- Added `android:enableOnBackInvokedCallback="true"` to enable predictive back gestures

### 2. android/src/org/haxe/lime/GameActivity.java
- Custom GameActivity with predictive back gesture support
- Automatically registers `OnBackInvokedCallback` on Android 13+
- Calls back to Haxe code when back gesture is detected

### 3. source/android/backend/AndroidBackHandler.hx
- JNI handler for Android 13+ back gestures
- `init()` method sets up the callback
- `handleBackPress()` method opens pause menu

### 4. source/Main.hx
- Added `backPressed` static flag for KEY events
- Added `ENTER_FRAME` listener to check back flag
- Initializes `AndroidBackHandler` for predictive gestures
- Opens pause menu when back is pressed

## How It Works

1. **Physical Back Button**: Uses KEY_DOWN/KEY_UP events → sets `backPressed` flag → opens pause menu in `onEnterFrame`

2. **Predictive Back Gesture (Edge Swipe)**: 
   - GameActivity receives `onBackInvoked()` callback
   - Calls `handleBackPress()` via JNI
   - Opens pause menu directly

## Testing

After making these changes:
1. Rebuild the Android app: `lime build android -release`
2. Install to device
3. Test with edge swipe back gesture
4. The pause menu should appear instead of exiting to home screen

## Notes

- Physical back button works immediately
- Edge swipe gestures require the custom GameActivity.java
- This is required for Android 13+ compliance
- Android 16 enforces this more strictly
