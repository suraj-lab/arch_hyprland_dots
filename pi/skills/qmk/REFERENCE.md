# QMK Reference

Detailed reference material for the QMK skill. Use when command workflow alone is not enough.

## QMK CLI Commands Reference

### Environment & Setup
- `qmk doctor` — Validates your QMK build environment, dependencies, and toolchains. **Run this first if compilation fails.**
- `qmk env` — Prints environment information (Python version, ARM toolchain, etc.).
- `qmk setup` — Initial setup of QMK build environment (rarely needed after initial install).
- `qmk config` — Read and write persistent QMK configuration settings.

### Compilation & Flashing
- `qmk compile -kb <keyboard> -km <keymap>` — Compile without flashing.
- `qmk flash -kb <keyboard> -km <keymap>` — Compile and flash automatically.
- `qmk clean` — Clean up the `.build/` folder. **Use this if compiling acts strangely after a git pull or firmware update.**
- `qmk find` — Find builds which match supplied search criteria.
- `qmk lint` — Check keyboard and keymap for common mistakes (syntax, unused layers, etc.).

### Keyboard Information
- `qmk info -kb zsa/moonlander` — Display keyboard information (layouts, features, pin mappings).
- `qmk list-keyboards` — List all available keyboards in the firmware.
- `qmk list-keymaps -kb zsa/moonlander` — List all keymaps for your keyboard.
- `qmk list-layouts -kb zsa/moonlander` — List available layouts for your keyboard.

### Format Conversion
- `qmk c2json <keymap.c>` — Convert a `keymap.c` file to `keymap.json` format.
- `qmk json2c <keymap.json>` — Convert a `keymap.json` file to `keymap.c` format.
- `qmk via2json <via-backup.json>` — Convert a VIA backup to keymap.json format.

### Debugging
- `qmk console` — Acquire debugging information from USB HID devices. Displays raw HID reports and debug messages from the keyboard.

### Maintenance
- `git pull upstream master` (run from the qmk_firmware root) — Pull the latest QMK upstream changes. **Always run `qmk clean` after this.**
- `qmk git-submodule` — Manage git submodules (ChibiOS, etc.).

---

## Common Keycodes Reference

### Basic Keys
- `KC_A` through `KC_Z` — Letter keys
- `KC_1` through `KC_0` — Number row
- `KC_SPACE`, `KC_TAB`, `KC_ENTER`, `KC_BSPC` — Common keys
- `KC_ESCAPE`, `KC_DELETE`, `KC_INSERT`, `KC_HOME`, `KC_END`, `KC_PGUP`, `KC_PGDN`

### Modifiers
- `KC_LSFT`, `KC_RSFT` — Left/Right Shift
- `KC_LCTL`, `KC_RCTL` — Left/Right Control
- `KC_LALT`, `KC_RALT` — Left/Right Alt
- `KC_LGUI`, `KC_RGUI` — Left/Right Super/Windows key

### Modifier Combinations (wrap a keycode)
- `LSFT(KC_2)` — Shift + 2
- `LCTL(KC_Z)` — Ctrl + Z
- `LGUI(KC_X)` — Windows/Cmd + X
- `LSFT(LCTL(KC_S))` — Shift + Ctrl + S

### Special Codes
- `KC_NO` — Do nothing (useful for disabling keys)
- `KC_TRANSPARENT` (or `_______`) — Pass through to the layer below
- `SAFE_RANGE` — Start of custom keycode range (e.g., `enum custom_keycodes { RGB_SLD = SAFE_RANGE, ... }`)

### Function Keys & Media
- `KC_F1` through `KC_F24` — Function keys
- `KC_MEDIA_PLAY_PAUSE`, `KC_MEDIA_NEXT_TRACK`, `KC_MEDIA_PREV_TRACK` — Media controls
- `KC_AUDIO_VOL_UP`, `KC_AUDIO_VOL_DOWN`, `KC_AUDIO_MUTE` — Volume control
- `KC_BRIGHTNESS_UP`, `KC_BRIGHTNESS_DOWN` — Screen brightness

### Mouse Keys
- `KC_MS_UP`, `KC_MS_DOWN`, `KC_MS_LEFT`, `KC_MS_RIGHT` — Mouse movement
- `KC_MS_BTN1`, `KC_MS_BTN2`, `KC_MS_BTN3` — Mouse buttons
- `KC_MS_WH_UP`, `KC_MS_WH_DOWN` — Mouse wheel

### Unicode & Special
- `KC_PSCR` — Print Screen
- `UK_PIPE` — UK-specific pipe character (`|`)
- `KC_NUBS` — Non-US backslash

---

## Layer Management Techniques

### Layer Types

**Momentary Layer (`MO`)**
- Activates a layer only while held down.
- Reverts to the previous layer when released.
- **Use Case:** Temporarily access symbols or numbers.
```c
MO(2)  // While held, use layer 2
```

**Layer Tap (`LT`)**
- Taps a keycode on single-tap, activates a layer on hold.
- **Use Case:** Efficient space bar that acts as space on tap, layer 2 on hold.
```c
LT(2, KC_SPACE)  // Tap = space, hold = layer 2
```

**Toggle (`TG`)**
- Toggles a layer on and off with each press.
- Remains active until pressed again.
- **Use Case:** Sticky layers (like a WASD gaming layer).
```c
TG(1)  // Press = activate layer 1, press again = deactivate
```

**Turn On (`TO`)**
- Turns on a specific layer and turns off all others.
- One-way switch (doesn't toggle back).
- **Use Case:** Switching to a completely different layout (Mac vs. PC mode).
```c
TO(4)  // Switch exclusively to layer 4
```

### Example Usage (from your keymap)
```c
KC_SPACE, TG(1), TG(2),  // Layer toggles on thumb cluster
```

---

## Macros & String Output

### Simple String Output (`SEND_STRING`)
Send predefined text strings via a keycode:
```c
enum custom_keycodes {
  EMAIL = SAFE_RANGE,
  GREETING,
};

bool process_record_user(uint16_t keycode, keyrecord_t *record) {
  switch (keycode) {
    case EMAIL:
      if (record->event.pressed) {
        SEND_STRING("your.email@example.com");
      }
      return false;
    case GREETING:
      if (record->event.pressed) {
        SEND_STRING("Hello, world!");
      }
      return false;
  }
  return true;
}
```

### Macro with Delays
```c
case MACRO_NAME:
  if (record->event.pressed) {
    SEND_STRING("Text" SS_DELAY(200) "more text");  // 200ms delay between
  }
  return false;
```

### Process Record User (for custom logic)
Override `process_record_user()` to intercept keypresses before they're sent:
```c
bool process_record_user(uint16_t keycode, keyrecord_t *record) {
  switch (keycode) {
    case QK_MACRO_0:  // Your custom macro
      if (record->event.pressed) {
        // Code here runs on key down
      } else {
        // Code here runs on key up
      }
      return false;  // Skip default QMK processing
  }
  return true;  // Continue with default processing
}
```

### Your Current Macro Usage
- `QK_MACRO_0` — Defined in Layer 4 (Mac/Productivity) on the right index finger. Currently mapped but not yet implemented in `process_record_user()`.

---

## Config File Reference

### `config.h`
Keyboard-wide compile-time settings. For your Moonlander layout:

```c
#define TAPPING_TERM 200  // Tap Dance timeout (ms). Increase if double-taps feel sluggish.
#define ONESHOT_TIMEOUT 5000  // One-shot modifier timeout (ms)
#define DEBOUNCE 5  // Debounce delay (ms). Higher = more stable but slower response.
#define PERMISSIVE_HOLD  // Treat mod-tap as a hold if another key is pressed (less strict)
#define IGNORE_MOD_TAP_INTERRUPT  // More strict: require full tap time before registering
```

### `rules.mk`
Enables/disables specific firmware features:

```makefile
MOUSEKEY_ENABLE = yes   # Mouse key support
RGB_MATRIX_ENABLE = yes  # Per-key RGB lighting (your keyboard uses this)
RGBLIGHT_ENABLE = no     # Underglow RGB (disable if using RGB_MATRIX)
TAP_DANCE_ENABLE = yes   # Tap dance support (required for your layout)
AUDIO_ENABLE = no        # Audio/beep support
ENCODER_ENABLE = yes     # Rotary encoder support (if your keyboard has one)
OLED_ENABLE = yes        # OLED display support (Moonlander has this)
```

Your current `rules.mk` defines custom features specific to the Moonlander.

---

## Debugging Techniques

### Using `qmk console`
```bash
qmk console
```
Displays raw HID reports from your keyboard in real-time. Useful for:
- Checking if keypresses are registering at the firmware level.
- Detecting ghost presses or stuck keys.
- Monitoring layer changes.

### Serial Debugging
Enable in `config.h`:
```c
#define DEBUG_ENABLE
```
Then use in code:
```c
dprintf("Layer: %u, Key: %u\n", current_layer, keycode);
```
Output appears in `qmk console`.

### Build Output
- **"Size before/after"** — Shows firmware binary size. If it exceeds device limit, disable features in `rules.mk`.
- **Compiler warnings** — Review carefully; they often indicate real issues.
- **"undefined reference"** — Function called but not defined. Check `process_record_user()` and enum declarations.

### Testing Specific Keys
Create a minimal test keymap to isolate issues:
```bash
qmk compile -kb zsa/moonlander -km default  # Test against default layout
```

---

## Common Compilation Errors

### "undefined reference to `..."
**Cause:** Function called but not defined or declared.
**Fix:** Check that `process_record_user()`, tap dance functions, or macros are properly declared before `tap_dance_actions[]`.

### "expected declaration specifiers or '...' before '{' token"
**Cause:** Syntax error (missing semicolon, mismatched braces).
**Fix:** Review the error line and surrounding code. Check for typos in keycodes.

### "error: 'SAFE_RANGE' undeclared"
**Cause:** `#include` is missing or `SAFE_RANGE` is used before the enum.
**Fix:** Ensure `#include QMK_KEYBOARD_H` is at the top of your file.

### Firmware Too Large
**Cause:** Binary size exceeds device memory.
**Fix:** Disable unused features in `rules.mk`:
```makefile
MOUSEKEY_ENABLE = no   # Disable if not using mouse keys
AUDIO_ENABLE = no      # Disable if not using audio
```

### "error: unknown type name 'tap_dance_state_t'"
**Cause:** Tap Dance feature not enabled.
**Fix:** Add to `rules.mk`:
```makefile
TAP_DANCE_ENABLE = yes
```

---

## RGB/LED Troubleshooting

### Per-Layer RGB (Your Setup)
Your layout uses layer-specific RGB colors via the `ledmap[][]` array. Each layer has its own color scheme.

**If LEDs don't change colors on layer switch:**
- Check that `rgb_matrix_indicators_user()` includes a case for your layer.
- Verify `RGB_MATRIX_ENABLE = yes` in `rules.mk`.
- Test with `qmk info -kb zsa/moonlander` to confirm RGB is enabled.

**If LEDs are stuck on one color:**
- Recompile and reflash: `qmk flash -kb zsa/moonlander -km new`
- Check for corrupted `rgb_matrix_config` in `keyboard_post_init_user()`.

**To disable RGB entirely (saves firmware space):**
In `rules.mk`:
```makefile
RGB_MATRIX_ENABLE = no
```
Remove `rgb_matrix_indicators_user()` and `ledmap[][]` from `keymap.c`.

### RGB Brightness & Modes
Controlled via keycodes in Layer 2:
- `RGB_VAD` — RGB Value Down (brightness)
- Custom HSV values like `HSV_0_255_255` — Hue, Saturation, Value controls

---

## Debounce & Debounce Algorithm Selection

### Debounce Settings in `config.h`
```c
#define DEBOUNCE 5  // Milliseconds to wait for switch to stabilize
```
- **Lower (3-5):** Faster response, but more prone to ghost presses.
- **Higher (10-15):** More stable, but slightly slower (not noticeable).

### Debounce Algorithm Selection (in `rules.mk`)
```makefile
DEBOUNCE_TYPE = sym_defer_g  # Default: symmetric deferred, global
```

**Common types:**
- `eager_pk` — Fast but less stable; useful for low-bounce switches.
- `sym_defer_g` — Balanced; good default.
- `sym_defer_pr` — Per-row debouncing; uses more resources.
- `adaptive` — Adjusts debounce dynamically (experimental).

**For Moonlander with Gateron switches:** `sym_defer_g` is usually fine. Increase `DEBOUNCE` to 8-10 if you get ghost presses.

---

## Moonlander-Specific Settings

### OLED Display
The Moonlander has a small OLED screen. Enable in `rules.mk`:
```makefile
OLED_ENABLE = yes
```

Display current layer or custom text:
```c
bool oled_task_user(void) {
  oled_write_P(PSTR("Layer: "), false);
  oled_write(get_u8_str(get_highest_layer(layer_state), ' '), false);
  return false;
}
```

### Encoders
If your Moonlander revision has rotary encoders, define them in `config.h`:
```c
#define ENCODER_MAP_ENABLE
```

Map encoder behavior by layer:
```c
const uint16_t PROGMEM encoder_map[][NUM_ENCODERS][2] = {
  [0] = { ENCODER_CCW_CW(KC_VOLD, KC_VOLU) },  // Layer 0: Volume
  [1] = { ENCODER_CCW_CW(KC_LEFT, KC_RIGHT) }, // Layer 1: Arrow keys
};
```

### Thumb Cluster Optimization
The Moonlander's thumb cluster is ergonomically positioned. Maximize with:
- **Layer toggles** (`TG`) for frequently-used layers.
- **Layer taps** (`LT`) for dual-purpose keys (modifier + layer).
- **One-shot modifiers** for clean chaining.

Current setup: Space, Layer Toggles (1-4), and Tap Dance on thumbs—excellent ergonomic layout.

### Reva vs. Older Revisions
Your keyboard is a **ZSA Moonlander Mark I Rev A (reva)**. Newer revisions may have different pin mappings or LED counts. Check the official ZSA documentation if flashing fails.

---

## Performance Optimization

### Firmware Size Management
Check size after compilation:
```
Size after:
   text      data       bss       dec       hex    filename
      0     66056         0     66056     10208    zsa_moonlander_reva_new.bin
```
The Moonlander has ~256KB flash. Your current size (66KB) is healthy.

**To reduce size if needed:**
1. Disable unused features in `rules.mk`:
   ```makefile
   RGB_MATRIX_ENABLE = no     # Saves ~10KB
   MOUSEKEY_ENABLE = no       # Saves ~5KB
   AUDIO_ENABLE = no          # Saves ~3KB
   TAP_DANCE_ENABLE = no      # Saves ~2KB
   ```

2. Use `LTO_ENABLE = yes` in `rules.mk` for link-time optimization (saves 5-10%):
   ```makefile
   LTO_ENABLE = yes
   ```

3. Simplify `ledmap[][]` (reduce RGB per-layer colors).

### Compilation Speed
- First compile: Slow (full rebuild).
- Subsequent compiles: Fast (incremental).
- To force clean rebuild:
  ```bash
  qmk clean && qmk compile -kb zsa/moonlander -km new
  ```

### Response Time Optimization
- **Lower debounce:** More responsive but less stable.
- **TAPPING_TERM:** Lower = faster tap recognition, higher = allows slower typists. Default: 200ms.
  ```c
  #define TAPPING_TERM 150  // Faster tap recognition
  ```
- **Reduce RGB animations** if running RGB on every layer (uses CPU cycles).

---

## Code Gotchas

### Tap Dance (`ACTION_TAP_DANCE_FN_ADVANCED`)
- **The Issue:** `DOUBLE_TAP` inputs will be swallowed entirely (printing nothing) if the case is not explicitly handled.
- **The Fix:** You *must* map `DOUBLE_TAP` inside the switch statements for both the `_finished` and `_reset` functions.
- **Example:**
  ```c
  // In the _finished function
  case DOUBLE_TAP: register_code16(KC_X); unregister_code16(KC_X); register_code16(KC_X); break;
  
  // In the _reset function
  case DOUBLE_TAP: unregister_code16(KC_X); break;
  ```

### RGB Matrix Indicators
- Per-layer RGB maps are controlled manually in `rgb_matrix_indicators_user()`. 
- **Ensure any new layer added to the keymap array also has a corresponding switch case in this function, otherwise the keyboard will go dark or display the wrong layer color.**
- Example:
  ```c
  bool rgb_matrix_indicators_user(void) {
    switch (biton32(layer_state)) {
      case 0: set_layer_color(0); break;
      case 1: set_layer_color(1); break;
      // ... add cases for each layer
    }
    return false;
  }
  ```

### Enum Conflicts
- **Issue:** Custom keycode enums must start after `SAFE_RANGE` to avoid conflicts with QMK's built-in codes.
- **Fix:**
  ```c
  enum custom_keycodes {
    RGB_SLD = SAFE_RANGE,  // Always start with SAFE_RANGE
    HSV_0_255_255,
    HSV_86_255_128,
  };
  ```

### Layer State Checking
- Use `biton32(layer_state)` to get the current highest layer (0-indexed).
- Use `layer_state_is(n)` to check if a specific layer is active.
  ```c
  if (layer_state_is(1)) {
    // Layer 1 is active
  }
  ```
