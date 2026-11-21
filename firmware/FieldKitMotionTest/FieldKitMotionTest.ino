#include <Wire.h>

uint8_t imuAddress = 0;

bool readRegisters(uint8_t address, uint8_t reg, uint8_t *data, uint8_t count) {
  Wire1.beginTransmission(address);
  Wire1.write(reg);
  if (Wire1.endTransmission() != 0) return false;
  if (Wire1.requestFrom(address, count) != count) return false;
  for (uint8_t index = 0; index < count; index++) data[index] = Wire1.read();
  return true;
}

bool writeRegister(uint8_t address, uint8_t reg, uint8_t value) {
  Wire1.beginTransmission(address);
  Wire1.write(reg);
  Wire1.write(value);
  return Wire1.endTransmission() == 0;
}

void setup() {
  Serial.begin(115200);
#ifdef PIN_LSM6DS3TR_C_POWER
  pinMode(PIN_LSM6DS3TR_C_POWER, OUTPUT);
  NRF_P1->PIN_CNF[8] = (NRF_P1->PIN_CNF[8] & ~GPIO_PIN_CNF_DRIVE_Msk) | (GPIO_PIN_CNF_DRIVE_H0H1 << GPIO_PIN_CNF_DRIVE_Pos);
  digitalWrite(PIN_LSM6DS3TR_C_POWER, HIGH);
#endif
  while (!Serial) delay(20);
  Serial.println("FieldKit USB connected");
  delay(25);
  Wire1.begin();
  for (uint8_t address = 0x6A; address <= 0x6B; address++) {
    Serial.print("Probing I2C address ");
    Serial.println(address, HEX);
    delay(100);
    uint8_t id = 0;
    if (readRegisters(address, 0x0F, &id, 1) && (id == 0x69 || id == 0x6A) &&
        writeRegister(address, 0x12, 0x44) && writeRegister(address, 0x10, 0x40)) {
      imuAddress = address;
      break;
    }
  }
}

void loop() {
  if (!Serial) {
    delay(20);
    return;
  }
  uint8_t data[6];
  if (!imuAddress || !readRegisters(imuAddress, 0x28, data, sizeof(data))) {
    Serial.println("ERROR: No accelerometer data");
    delay(1000);
    return;
  }
  Serial.print(millis());
  for (uint8_t axis = 0; axis < 3; axis++) {
    const uint8_t offset = axis * 2;
    const int16_t raw = static_cast<int16_t>(data[offset] | (uint16_t(data[offset + 1]) << 8));
    Serial.print(',');
    Serial.print(raw * 0.000061f, 4);
  }
  Serial.println();
  delay(20);
}
