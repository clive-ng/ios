# 🏛️ Museum Explorer (iOS Native App)

Welcome to the native iOS version of the Museum Explorer app! 

This project uses **CoreBluetooth** to scan for physical museum beacons and calculate proximity, and **MQTT (via CocoaMQTT)** to send remote control signals to IoT exhibits over the cloud. 

Because we are dealing with physical hardware (Bluetooth) and background networks, **this app must be tested on a real iPhone**. The Xcode Simulator does not support Bluetooth scanning.

Follow these instructions step-by-step to set up your environment, install the required libraries, and deploy the app to your phone.

---

## 🛠 Prerequisites
* A Mac running Xcode 15 or later.
* A physical iPhone (updated to iOS 16+).
* A standard USB/USB-C cable to connect your phone to your Mac.
* A free Apple ID (used for signing the app).

---

## Step 1: Create the Project
1. Open Xcode and click **Create a new Xcode project**.
2. Select **iOS** at the top, choose **App**, and click Next.
3. Name the product **MuseumExplorer**.
4. Make sure the Interface is set to **SwiftUI** and the Language is **Swift**.
5. Save the project to your computer.

---

## Step 2: Install the MQTT Library
iOS does not have a built-in MQTT client. We will use a popular third-party library called **CocoaMQTT**.

1. In Xcode, look at the top menu bar and click **File > Add Package Dependencies...**
2. In the search bar in the top right corner, paste this exact URL:
   `https://github.com/emqx/CocoaMQTT`
3. Set the "Dependency Rule" to **Up to Next Major Version**.
4. Click the blue **Add Package** button at the bottom right.
5. When prompted again, ensure `CocoaMQTT` is checked and added to your app target, then click **Add Package** one last time.

---

## Step 3: Add Bluetooth Privacy Permissions
Apple enforces strict privacy rules. If an app tries to use Bluetooth without asking the user first, the app will instantly crash. We need to add a permission message to the project.

1. In the left sidebar (Project Navigator), click the **blue project icon** at the very top.
2. In the main window, click your app's name under **Targets**.
3. Click the **Info** tab at the top.
4. Hover your mouse over any existing item in the "Custom iOS Target Properties" list and click the tiny **+** button.
5. In the new row, type exactly this into the Key column and press Return:
   `Privacy - Bluetooth Always Usage Description`
6. In the **Value** column for that row, double-click the empty space and type the message the user will see:
   *Museum Explorer needs Bluetooth to find your distance to nearby exhibits.*

---

## Step 4: Add the Code
1. In the left sidebar, click on `ContentView.swift`.
2. Delete everything in the file.
3. Copy and paste the provided application code below:

<details>
<summary><b>Click to expand and copy ContentView.swift</b></summary>

```swift
//
//  ContentView.swift
//  Museum Explorer
//

import SwiftUI
import CoreBluetooth
import Combine
import CocoaMQTT

// MARK: - App State & Managers

final class MuseumAppManager: NSObject, ObservableObject, CBCentralManagerDelegate {
    
    @Published var isScanning = false
    @Published var beaconName = "CONNECT TO BEACON"
    @Published var distance: Double? = nil
    @Published var proximityState: ProximityState = .outOfRange
    @Published var mqttStatus = "Connecting to Cloud Control..."
    @Published var isMqttConnected = false
    
    private var centralManager: CBCentralManager!
    private var smoothedRssi: Double? = nil
    private let alpha: Double = 0.7
    
    private var mqttClient: CocoaMQTT!
    private let mqttTopic = "exhibit/clive/lights"
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
        setupMQTT()
    }
    
    private func setupMQTT() {
        let clientID = "clive_combined_" + String(Int.random(in: 1000...9999))
        mqttClient = CocoaMQTT(clientID: clientID, host: "broker.hivemq.com", port: 1883)
        mqttClient.keepAlive = 60
        
        mqttClient.didConnectAck = { [weak self] mqtt, ack in
            DispatchQueue.main.async {
                if ack == .accept {
                    self?.isMqttConnected = true
                    self?.mqttStatus = "● CLOUD CONTROL READY (4G)"
                } else {
                    self?.mqttStatus = "Cloud connection rejected."
                }
            }
        }
        
        mqttClient.didDisconnect = { [weak self] mqtt, err in
            DispatchQueue.main.async {
                self?.isMqttConnected = false
                self?.mqttStatus = "Cloud Offline. Retrying..."
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    self?.mqttClient.connect()
                }
            }
        }
        
        _ = mqttClient.connect()
    }
    
    func sendMqttCommand(_ command: String) {
        guard isMqttConnected else { return }
        mqttClient.publish(mqttTopic, withString: command)
    }
    
    func toggleScanning() {
        if isScanning {
            centralManager.stopScan()
            isScanning = false
            beaconName = "CONNECT TO BEACON"
            distance = nil
            proximityState = .outOfRange
            smoothedRssi = nil
        } else {
            guard centralManager.state == .poweredOn else { return }
            isScanning = true
            beaconName = "Searching..."
            centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        }
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state != .poweredOn {
            isScanning = false
            beaconName = "CONNECT TO BEACON"
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        
        let deviceName = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? "Unknown"
        print("Heard device: \(deviceName) | RSSI: \(RSSI)")
        
        guard deviceName == "Museum_Beacon" else { return }
        
        let currentRssi = RSSI.doubleValue
        guard currentRssi < 0 else { return } 
        
        DispatchQueue.main.async {
            self.beaconName = "Beacon: \(deviceName)"
            
            if self.smoothedRssi == nil {
                self.smoothedRssi = currentRssi
            } else {
                self.smoothedRssi = (self.alpha * currentRssi) + ((1 - self.alpha) * self.smoothedRssi!)
            }
            
            let txPower = -59.0
            let ratio = (txPower - self.smoothedRssi!) / 20.0
            let calculatedDistance = pow(10.0, ratio)
            
            self.distance = calculatedDistance
            self.updateProximityState(distance: calculatedDistance)
        }
    }
    
    private func updateProximityState(distance: Double) {
        if distance > 5.0 { proximityState = .outOfRange }
        else if distance > 3.0 { proximityState = .signalDetected }
        else if distance > 1.5 { proximityState = .gettingCloser }
        else if distance > 0.5 { proximityState = .veryClose }
        else { proximityState = .artifactReached }
    }
}

// MARK: - Proximity States

enum ProximityState: String {
    case outOfRange = "1. Out of range"
    case signalDetected = "2. Signal detected"
    case gettingCloser = "3. Getting closer"
    case veryClose = "4. Very close"
    case artifactReached = "5. Artifact reached!"
    
    var color: Color {
        switch self {
        case .outOfRange: return Color(red: 127/255, green: 140/255, blue: 141/255)
        case .signalDetected: return Color(red: 52/255, green: 152/255, blue: 219/255)
        case .gettingCloser: return Color(red: 46/255, green: 204/255, blue: 113/255)
        case .veryClose: return Color(red: 230/255, green: 126/255, blue: 34/255)
        case .artifactReached: return Color(red: 231/255, green: 76/255, blue: 60/255)
        }
    }
}

// MARK: - UI

struct ContentView: View {
    @StateObject private var appManager = MuseumAppManager()
    
    var body: some View {
        ZStack {
            Color(red: 18/255, green: 18/255, blue: 18/255).ignoresSafeArea()
            
            VStack(spacing: 20) {
                Text("Museum Explorer")
                    .font(.largeTitle).fontWeight(.bold).foregroundColor(.white).padding(.top, 20)
                
                // Beacon Card
                VStack(spacing: 15) {
                    Button(action: { appManager.toggleScanning() }) {
                        Text(appManager.beaconName)
                            .font(.headline).fontWeight(.bold).foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding()
                            .background(Color(red: 52/255, green: 152/255, blue: 219/255))
                            .cornerRadius(8)
                    }
                    
                    if let dist = appManager.distance {
                        Text(String(format: "Distance: %.2fm", dist))
                            .font(.title3).fontWeight(.bold).foregroundColor(Color(red: 241/255, green: 196/255, blue: 15/255))
                    } else {
                        Text("Distance: --m")
                            .font(.title3).fontWeight(.bold).foregroundColor(Color(red: 241/255, green: 196/255, blue: 15/255))
                    }
                    
                    Text(appManager.proximityState.rawValue)
                        .font(.headline).fontWeight(.bold).foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding()
                        .background(appManager.proximityState.color)
                        .cornerRadius(8)
                        .animation(.easeInOut(duration: 0.5), value: appManager.proximityState)
                }
                .padding().background(Color(red: 30/255, green: 30/255, blue: 30/255)).cornerRadius(15)
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color(red: 51/255, green: 51/255, blue: 51/255), lineWidth: 1))
                
                // Control Card
                VStack(spacing: 15) {
                    Text(appManager.mqttStatus)
                        .font(.caption).fontWeight(appManager.isMqttConnected ? .bold : .regular)
                        .foregroundColor(appManager.isMqttConnected ? Color(red: 46/255, green: 204/255, blue: 113/255) : Color.gray)
                    
                    VStack(spacing: 10) {
                        controlButton(title: "TURN ON", bgColor: Color(red: 46/255, green: 204/255, blue: 113/255), fgColor: .white, command: "1")
                        controlButton(title: "TURN OFF", bgColor: Color(red: 231/255, green: 76/255, blue: 60/255), fgColor: .white, command: "0")
                        controlButton(title: "SLOW BLINK", bgColor: Color(red: 241/255, green: 196/255, blue: 15/255), fgColor: .black, command: "2")
                        controlButton(title: "FAST STROBE", bgColor: Color(red: 241/255, green: 196/255, blue: 15/255), fgColor: .black, command: "3")
                    }
                    .disabled(!appManager.isMqttConnected)
                    .opacity(appManager.isMqttConnected ? 1.0 : 0.2)
                }
                .padding().background(Color(red: 30/255, green: 30/255, blue: 30/255)).cornerRadius(15)
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color(red: 51/255, green: 51/255, blue: 51/255), lineWidth:
