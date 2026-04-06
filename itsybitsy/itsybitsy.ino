/*
 * ItsyBitsy -> DE10 FPGA Game Controller
 * 
 * Buttons: GPIO 13, 12, 11, 10 (internal pull-up, active LOW)
 * UART TX:  Serial1 @ 115200 baud -> FPGA UART_RX pin
 * OLED:     128x64 I2C (SSD1306), address 0x3C
 * 
 * Libraries needed (install via Library Manager):
 *   - Adafruit SSD1306
 *   - Adafruit GFX Library
 *
 * UART byte protocol:
 *   0x01 -> Button 0 (pin 13) -> Tone 440Hz
 *   0x02 -> Button 1 (pin 12) -> Tone 523Hz
 *   0x04 -> Button 2 (pin 11) -> Tone 659Hz
 *   0x08 -> Button 3 (pin 10) -> Tone 784Hz
 */

#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>

// ── OLED ──────────────────────────────────────────────────────────────────────
#define SCREEN_WIDTH  128
#define SCREEN_HEIGHT  64
#define OLED_RESET     -1   // share Arduino reset
#define OLED_ADDR    0x3C

Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, OLED_RESET);

// ── Button pins & their UART bytes ────────────────────────────────────────────
const int   BTN_PINS[4]  = { 13, 12, 11, 10 };
const byte  BTN_BYTES[4] = { 0x01, 0x02, 0x04, 0x08 };
const char* BTN_NOTES[4] = { "440 Hz", "523 Hz", "659 Hz", "784 Hz" };
const char* BTN_NAMES[4] = { "BTN 0", "BTN 1", "BTN 2", "BTN 3" };

// ── Debounce state ────────────────────────────────────────────────────────────
bool     lastState[4]    = { HIGH, HIGH, HIGH, HIGH };
bool     currentState[4] = { HIGH, HIGH, HIGH, HIGH };
uint32_t lastDebounce[4] = { 0, 0, 0, 0 };
#define DEBOUNCE_MS 30

// ── Display state ─────────────────────────────────────────────────────────────
int      lastPressed   = -1;   // index of last button, -1 = none yet
uint32_t lastPressTime = 0;
#define  DISPLAY_HOLD_MS 1200  // how long to show the "sent" message

// ──────────────────────────────────────────────────────────────────────────────

void setup() {
  // Buttons with internal pull-ups
  for (int i = 0; i < 4; i++) {
    pinMode(BTN_PINS[i], INPUT_PULLUP);
  }

  // UART to FPGA — use Serial1 on ItsyBitsy (TX pin)
  Serial1.begin(115200);

  // Debug serial (USB) — optional
  Serial.begin(115200);

  // OLED init
  if (!display.begin(SSD1306_SWITCHCAPVCC, OLED_ADDR)) {
    // If OLED fails, just hang with LED blink
    pinMode(LED_BUILTIN, OUTPUT);
    while (true) {
      digitalWrite(LED_BUILTIN, !digitalRead(LED_BUILTIN));
      delay(200);
    }
  }

  // Boot screen
  showBoot();
  delay(1200);
  showIdle();
}

void loop() {
  uint32_t now = millis();

  for (int i = 0; i < 4; i++) {
    bool reading = digitalRead(BTN_PINS[i]);

    // Reset debounce timer on state change
    if (reading != lastState[i]) {
      lastDebounce[i] = now;
    }

    // Only act after debounce period
    if ((now - lastDebounce[i]) > DEBOUNCE_MS) {
      if (reading != currentState[i]) {
        currentState[i] = reading;

        // Active LOW — falling edge = press
        if (currentState[i] == LOW) {
          sendButton(i);
          lastPressed   = i;
          lastPressTime = now;
          showSent(i);
        }
      }
    }

    lastState[i] = reading;
  }

  // Return to idle screen after hold time
  if (lastPressed != -1 && (now - lastPressTime) > DISPLAY_HOLD_MS) {
    lastPressed = -1;
    showIdle();
  }
}

// ── Send UART byte to FPGA ────────────────────────────────────────────────────
void sendButton(int idx) {
  Serial1.write(BTN_BYTES[idx]);
  Serial.print("Sent: 0x");
  if (BTN_BYTES[idx] < 0x10) Serial.print("0");
  Serial.println(BTN_BYTES[idx], HEX);
}

// ── OLED Screens ──────────────────────────────────────────────────────────────

void showBoot() {
  display.clearDisplay();
  display.setTextColor(SSD1306_WHITE);

  // Title
  display.setTextSize(1);
  display.setCursor(22, 4);
  display.print("FPGA AUDIO GAME");

  // Divider
  display.drawFastHLine(0, 16, 128, SSD1306_WHITE);

  display.setTextSize(1);
  display.setCursor(28, 24);
  display.print("ItsyBitsy TX");
  display.setCursor(16, 36);
  display.print("115200 baud UART");

  // Bottom border
  display.drawRect(0, 0, 128, 64, SSD1306_WHITE);

  display.display();
}

void showIdle() {
  display.clearDisplay();
  display.setTextColor(SSD1306_WHITE);

  // Header
  display.setTextSize(1);
  display.setCursor(34, 2);
  display.print("WAITING...");
  display.drawFastHLine(0, 13, 128, SSD1306_WHITE);

  // Show all 4 buttons with their bytes
  for (int i = 0; i < 4; i++) {
    int col = (i < 2) ? 0 : 64;
    int row = 18 + (i % 2) * 22;

    // Small box around each button
    display.drawRect(col + 2, row - 2, 60, 18, SSD1306_WHITE);

    display.setTextSize(1);
    display.setCursor(col + 6, row + 1);
    display.print(BTN_NAMES[i]);
    display.print(": ");

    // Hex byte in slightly offset position
    display.setCursor(col + 6, row + 10);
    display.print("0x");
    if (BTN_BYTES[i] < 0x10) display.print("0");
    display.print(BTN_BYTES[i], HEX);
    display.print(" ");
    display.print(BTN_NOTES[i]);
  }

  display.display();
}

void showSent(int idx) {
  display.clearDisplay();
  display.setTextColor(SSD1306_WHITE);

  // Invert header bar
  display.fillRect(0, 0, 128, 14, SSD1306_WHITE);
  display.setTextColor(SSD1306_BLACK);
  display.setTextSize(1);
  display.setCursor(36, 3);
  display.print("SENT!");
  display.setTextColor(SSD1306_WHITE);

  // Big hex byte
  display.setTextSize(3);
  char hexStr[5];
  snprintf(hexStr, sizeof(hexStr), "0x%02X", BTN_BYTES[idx]);
  // Center the text (3x font = 18px wide per char, ~5 chars)
  int textW = strlen(hexStr) * 18;
  int xPos  = (128 - textW) / 2;
  display.setCursor(xPos, 18);
  display.print(hexStr);

  // Button name and note below
  display.setTextSize(1);
  display.setCursor(28, 46);
  display.print(BTN_NAMES[idx]);
  display.print(" -> ");
  display.print(BTN_NOTES[idx]);

  // Bottom bar
  display.fillRect(0, 56, 128, 8, SSD1306_WHITE);
  display.setTextColor(SSD1306_BLACK);
  display.setTextSize(1);
  display.setCursor(22, 57);
  display.print("TX -> FPGA UART_RX");

  display.display();
}
