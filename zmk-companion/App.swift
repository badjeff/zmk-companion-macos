//
//  App.swift
//  zmk-companion
//
//  Created by Jeff on 8/17/24.
//

import SwiftUI
import CoreServices

import HotKey
import Carbon

@main
struct ZmkCompanionApp: App {
    
    @ObservedObject var model: AppModel

    @State var isInserted = true
    @State var isMenuPresented: Bool = false
    
    @State var colorIndex: Int = 0
    var colors: [NSColor] = [
        .white,
        .green,
        .orange
    ]
    var keyCombos: [KeyCombo] = [
        KeyCombo(key: .f17, modifiers: []),
        KeyCombo(key: .f19, modifiers: []),
        KeyCombo(key: .f20, modifiers: [])
    ]
    
    init() {
        model = AppModel()
        _ = model.forApp(self)
        model.updateMenuLabelColorIndex(0)
    }

    var body: some Scene {
        MenuBarExtra(isInserted: $isInserted) {
            AppMenu(model: self.model)
        } label: {
            let color = colors[colorIndex]
            let configuration = NSImage.SymbolConfiguration(pointSize: 16, weight: .light)
                                .applying(.init(paletteColors: [ color ]))
            let image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)
            let updateImage = image?.withSymbolConfiguration(configuration)
            Image(nsImage: updateImage!)
        }
        .menuBarExtraStyle(.window)
        .menuBarExtraAccess(isPresented: $isMenuPresented)
        .onChange(of: isMenuPresented, perform: { newVal in
            self.model.updateMenuAppearance(isMenuPresented)
        })
        .onChange(of: model.colorIndex, perform: { newVal in
            self.colorIndex = model.colorIndex
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
    func hasVolCfg() -> Bool {
        return volFaderCfg != nil
    }

    var app: ZmkCompanionApp? = nil
    var colorIndex: Int = 0
    var hotKeys: [HotKey] = []

    func forApp(_ newApp: ZmkCompanionApp) -> AppModel {
        app = newApp
        if app?.keyCombos.count ?? 0 > 0 {
            for (i, keyCombo) in app!.keyCombos.enumerated() {
                let hotkey = HotKey(keyCombo: keyCombo)
                hotkey.keyDownHandler = {
                    self.updateMenuLabelColorIndex(i)
                }
                hotKeys.append(hotkey)
            }
        }
        return self
    }

    func updateMenuLabelColorIndex(_ newColorIndex: Int) {
        colorIndex = newColorIndex
        print("colorIndex: \(colorIndex)")
        self.objectWillChange.send()
    }

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

        // comment below line if not using volume fader
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

        !self.model.hasVolCfg()
        ? Text("").fixedSize(horizontal: true, vertical: true).frame(width: 0, height: 0).padding(0)
        : Text(model.volFaderIsReady ? "Volume Fader Connected" : "No Volume Fader Is Connected")
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: 200, height: 12)
            .padding(8)

        !self.model.hasVolCfg()
        ? Text("").fixedSize(horizontal: true, vertical: true).frame(width: 0, height: 0).padding(0)
        : Text("Sound Volume: \( String(format: "%.0f", model.soundVolume * 100) )%")
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
