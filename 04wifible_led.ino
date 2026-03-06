#include <WiFi.h>
#include <PubSubClient.h>
#include <BLEDevice.h>
#include <BLEUtils.h>
#include <BLEBeacon.h>

// --- WiFi & MQTT Settings ---
const char* ssid = "Point";
const char* password = "ucaclive";
const char* mqtt_server = "broker.hivemq.com";
const char* topic = "exhibit/clive/lights"; 

// --- Hardware Settings ---
const int ledPin = 2;
int currentMode = 0;
bool ledState = false;
unsigned long previousMillis = 0;

WiFiClient espClient;
PubSubClient client(espClient);

// --- iBeacon Settings ---
#define BEACON_UUID "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
BLEAdvertising *pAdvertising;

void setupBeacon() {
  BLEDevice::init("Museum_Beacon");
  pAdvertising = BLEDevice::getAdvertising();
  
  BLEBeacon oBeacon = BLEBeacon();
  oBeacon.setManufacturerId(0x4C00); // Apple ID for iBeacon
  oBeacon.setProximityUUID(BLEUUID(BEACON_UUID));
  oBeacon.setMajor(1);
  oBeacon.setMinor(1);
  oBeacon.setSignalPower(-59); // Measured RSSI at 1 meter

  BLEAdvertisementData oAdvertisementData = BLEAdvertisementData();
  oAdvertisementData.setFlags(0x04); // BR_EDR_NOT_SUPPORTED
  
  std::string strServiceData = "";
  strServiceData += (char)26;     // Len
  strServiceData += (char)0xFF;   // Type
  strServiceData += oBeacon.getData(); 
  oAdvertisementData.addData(strServiceData);
  
  pAdvertising->setAdvertisementData(oAdvertisementData);
  pAdvertising->start();
  Serial.println("iBeacon is broadcasting...");
}

// --- MQTT Callback ---
void callback(char* topic, byte* payload, unsigned int length) {
  payload[length] = '\0';
  String message = String((char*)payload);
  currentMode = message.toInt();
  
  Serial.print("New Mode: ");
  Serial.println(currentMode);

  if (currentMode == 0) digitalWrite(ledPin, LOW);
  if (currentMode == 1) digitalWrite(ledPin, HIGH);
}

void reconnect() {
  while (!client.connected()) {
    Serial.print("Attempting MQTT connection...");
    if (client.connect("ESP32_Museum_Client")) {
      Serial.println("connected");
      client.subscribe(topic);
    } else {
      Serial.print("failed, rc=");
      Serial.print(client.state());
      delay(5000);
    }
  }
}

void setup() {
  Serial.begin(115200);
  pinMode(ledPin, OUTPUT);
  digitalWrite(ledPin, LOW);

  // 1. Start Bluetooth Beacon
  setupBeacon();

  // 2. Start WiFi
  WiFi.begin(ssid, password);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\nWiFi connected");

  // 3. Start MQTT
  client.setServer(mqtt_server, 1883);
  client.setCallback(callback);
}

void loop() {
  if (!client.connected()) {
    reconnect();
  }
  client.loop();

  // LED Animation Logic
  if (currentMode == 2 || currentMode == 3) {
    unsigned long currentMillis = millis();
    int speed = (currentMode == 2) ? 1000 : 100;
    if (currentMillis - previousMillis >= speed) {
      previousMillis = currentMillis;
      ledState = !ledState;
      digitalWrite(ledPin, ledState);
    }
  }
}
