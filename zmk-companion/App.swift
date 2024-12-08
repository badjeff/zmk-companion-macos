//
//  App.swift
//  zmk-companion
//
//  Created by Jeff on 8/17/24.
//

import SwiftUI
import CoreServices

@main
struct zmk_companion: App {
    
    let model: AppModel = AppModel()

    @State var pressed: Bool = false
    @State var isMenuPresented: Bool = false

    var body: some Scene {
        MenuBarExtra("ZMK Companion App", systemImage: "keyboard") {
            AppMenu(model: self.model)
        }
        .menuBarExtraStyle(.window)
        .menuBarExtraAccess(isPresented: $isMenuPresented)
        .onChange(of: isMenuPresented, perform: { newVal in
            self.model.updateMenuAppearance(isMenuPresented)
        })
    }

}

class AppModel: ObservableObject {
    
    struct VolFaderDevConfig {
        var vid: Int
        var pid: Int
        var productKey: String
        var usagePage: Int
        var usage: Int
    }
    var volFaderCfg: VolFaderDevConfig?

    var menuAppearance = false
    func updateMenuAppearance(_ newVal: Bool) {
        menuAppearance = newVal
        print(menuAppearance ? "menu appear!" : "menu disappear!")
        self.objectWillChange.send()
    }

    var volFaderIsReady = false
    func updateVolFaderIdReady(_ newVal: Bool) {
        volFaderIsReady = newVal
        print(volFaderIsReady ? "vol fader ready!" : "vol fader phew!")
        self.objectWillChange.send()
    }
    
    var soundVolume: Float = 0
    func changeSoundVolume(_ newVol: Float) -> Bool {
        guard newVol != soundVolume else { return false }
        soundVolume = newVol
        print("Sound Volume: \( soundVolume )")
        self.objectWillChange.send()
        return true
    }
    
    // properties to skip unnessary hid reporting
    var skipSendReport: Bool = false
    var hidReportVal: UInt8 = 0
    
    internal init() {
        
        self.volFaderCfg = VolFaderDevConfig(vid: 0x1D50, pid: 0x615E, productKey: "zero36", usagePage: 0x0C, usage: 0xE0)
        
        if (self.volFaderCfg != nil) {
            // Hid.manager.listHIDDevices(printLog: true)
            Hid.manager.didHidDevicesReported = { reportId in
                // print("hid reported")
                DispatchQueue.main.async {
                    if reportId == 5 {
                        let readVal = Hid.manager.readHIDReport(reportId: Int(reportId), reportLength: 2)
                        if (readVal.count == 2) {
                            let pVol = readVal[1]
                            self.skipSendReport = true
                            self.hidReportVal = pVol
                            let fVol = Float(pVol) / 100.0
                            // print("read hid value: \(fVol) (\( pVol )%)")
                            Sound.output.volume = fVol
                        }
                    }
                }
            }
            Hid.manager.didHidDevicesAdded = { inDevice in
                // print("hid added")
                DispatchQueue.main.async {
                    print("open hid device")
                    Hid.manager.openHID(device: inDevice)
                    if (Hid.manager.isOpen ?? false) {
                        try? Hid.manager.addHidDeviceReportObserver()
                        self.updateVolFaderIdReady(true)
                    }
                }
            }
            Hid.manager.didHidDevicesRemoved = { inDevice in
                // print("hid removed")
                DispatchQueue.main.async {
                    print("close hid device")
                    if (Hid.manager.isOpen ?? false) {
                        try? Hid.manager.removeHidDeviceReportObserver()
                        Hid.manager.closeHID()
                    }
                    self.updateVolFaderIdReady(false)
                }
            }
            try? Hid.manager.addHidDevicesAddRemoveObserver(vid: self.volFaderCfg!.vid,
                                                            pid: self.volFaderCfg!.pid,
                                                            productKey: self.volFaderCfg!.productKey,
                                                            usagePage: self.volFaderCfg!.usagePage,
                                                            usage: self.volFaderCfg!.usage)

            print("volume fader hid device observer set!")
        }
        
        Sound.output.didAudioDevicesChanged = {
            DispatchQueue.main.async {
                let vol = Sound.output.volume
                if self.changeSoundVolume(vol) {
                    if (Hid.manager.isOpen ?? false) {
                        let vol = UInt8(vol * 100)
                        if self.skipSendReport {
                            self.skipSendReport = false
                            return
                        }
                        if vol != self.hidReportVal {
                            let reportId: UInt8 = 4
                            Hid.manager.sendHIDReport(report: [ reportId, vol, 0, ])
                            self.hidReportVal = vol
                        }
                    }
                }
            }
        }
        try? Sound.output.addAudioDevicesChangeObserver()
        _ = self.changeSoundVolume(Sound.output.volume)

        print("all set!")
    }
    
}

struct AppMenu: View {
    
    @StateObject var model: AppModel
    
    @State var volume: Float = 0

    var body: some View {

        Text(model.volFaderIsReady ? "Volume Fader Connected" : "No Volume Fader Is Connected")
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: 200, height: 12)
            .padding(8)

        Text("Sound Volume: \( String(format: "%.0f", model.soundVolume * 100) )%")
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: 160, height: 20)
            .padding(8)

        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            Text("Quit")
                .frame(width: 80)
                .padding()
        }
            .buttonStyle(.bordered)
            .padding(8)
            .keyboardShortcut("q")
    }
}
