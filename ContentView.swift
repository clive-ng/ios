//
//  ContentView.swift
//  Museum Explorer
//

import SwiftUI
import CoreBluetooth
import Combine
// IMPORTANT: You must have CocoaMQTT installed via Swift Package Manager
import CocoaMQTT

// MARK: - App State & Managers

final class MuseumAppManager: NSObject, ObservableObject, CBCentralManagerDelegate {
    
    // UI State Published Variables
    @Published var isScanning = false
    @Published var beaconName = "CONNECT TO BEACON"
    @Published var distance: Double? = nil
    @Published var proximityState: ProximityState = .outOfRange
    @Published var mqttStatus = "Connecting to Cloud Control..."
    @Published var isMqttConnected = false
    
    // Bluetooth
    private var centralManager: CBCentralManager!
    private var smoothedRssi: Double? = nil
    private let alpha: Double = 0.7
    
    // MQTT
    private var mqttClient: CocoaMQTT!
    private let mqttTopic = "exhibit/clive/lights"
    
    override init() {
        super.init()
        // Initialize Bluetooth
        centralManager = CBCentralManager(delegate: self, queue: .main)
        // Initialize MQTT
        setupMQTT()
    }
    
    // MARK: - MQTT Logic
    
    private func setupMQTT() {
        let clientID = "clive_combined_" + String(Int.random(in: 1000...9999))
        // Using standard MQTT TCP port 1883 for iOS
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
                // Simple retry logic
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
    
    // MARK: - Bluetooth Logic
    
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
            
            // By passing 'nil' for services, iOS will look at ALL broadcasting devices
            // so we can catch the beacon by its name even if its UUID is hidden.
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
        
        // 1. Grab the device name (either from the peripheral or the broadcast data)
        let deviceName = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? "Unknown"
        
        // DEBUG: Prints every device it sees into the Xcode console at the bottom of your screen.
        print("Heard device: \(deviceName) | RSSI: \(RSSI)")
        
        // 2. STRICT FILTER: Only proceed if it is exactly "Museum_Beacon"
        guard deviceName == "Museum_Beacon" else { return }
        
        let currentRssi = RSSI.doubleValue
        guard currentRssi < 0 else { return } // Ignore invalid RSSI values
        
        DispatchQueue.main.async {
            // Update the UI with the confirmed beacon name
            self.beaconName = "Beacon: \(deviceName)"
            
            // RSSI Smoothing (Low-pass filter)
            if self.smoothedRssi == nil {
                self.smoothedRssi = currentRssi
            } else {
                self.smoothedRssi = (self.alpha * currentRssi) + ((1 - self.alpha) * self.smoothedRssi!)
            }
            
            // Calculate Distance
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
        case .outOfRange: return Color(red: 127/255, green: 140/255, blue: 141/255) // #7f8c8d
        case .signalDetected: return Color(red: 52/255, green: 152/255, blue: 219/255) // #3498db
        case .gettingCloser: return Color(red: 46/255, green: 204/255, blue: 113/255) // #2ecc71
        case .veryClose: return Color(red: 230/255, green: 126/255, blue: 34/255) // #e67e22
        case .artifactReached: return Color(red: 231/255, green: 76/255, blue: 60/255) // #e74c3c
        }
    }
}

// MARK: - UI

struct ContentView: View {
    @StateObject private var appManager = MuseumAppManager()
    
    var body: some View {
        ZStack {
            Color(red: 18/255, green: 18/255, blue: 18/255) // #121212
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Text("Museum Explorer")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.top, 20)
                
                // Beacon Card
                VStack(spacing: 15) {
                    Button(action: {
                        appManager.toggleScanning()
                    }) {
                        Text(appManager.beaconName)
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(red: 52/255, green: 152/255, blue: 219/255))
                            .cornerRadius(8)
                    }
                    
                    if let dist = appManager.distance {
                        Text(String(format: "Distance: %.2fm", dist))
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(Color(red: 241/255, green: 196/255, blue: 15/255)) // #f1c40f
                    } else {
                        Text("Distance: --m")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(Color(red: 241/255, green: 196/255, blue: 15/255))
                    }
                    
                    // Active State Display
                    Text(appManager.proximityState.rawValue)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(appManager.proximityState.color)
                        .cornerRadius(8)
                        .animation(.easeInOut(duration: 0.5), value: appManager.proximityState)
                }
                .padding()
                .background(Color(red: 30/255, green: 30/255, blue: 30/255)) // #1e1e1e
                .cornerRadius(15)
                .overlay(
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(Color(red: 51/255, green: 51/255, blue: 51/255), lineWidth: 1)
                )
                
                // Control Card
                VStack(spacing: 15) {
                    Text(appManager.mqttStatus)
                        .font(.caption)
                        .fontWeight(appManager.isMqttConnected ? .bold : .regular)
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
                .padding()
                .background(Color(red: 30/255, green: 30/255, blue: 30/255))
                .cornerRadius(15)
                .overlay(
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(Color(red: 51/255, green: 51/255, blue: 51/255), lineWidth: 1)
                )
                
                Spacer()
            }
            .padding()
        }
        .preferredColorScheme(.dark)
    }
    
    // Reusable Button Component
    private func controlButton(title: String, bgColor: Color, fgColor: Color, command: String) -> some View {
        Button(action: {
            appManager.sendMqttCommand(command)
        }) {
            Text(title)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(fgColor)
                .frame(maxWidth: .infinity)
                .padding()
                .background(bgColor)
                .cornerRadius(10)
        }
    }
}

#Preview {
    ContentView()
}
