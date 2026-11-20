import CoreGraphics
import Foundation

let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
    print("nao consegui listar janelas")
    exit(1)
}

var found = 0
for window in list {
    let owner = window[kCGWindowOwnerName as String] as? String ?? ""
    guard owner.contains("Letras") else { continue }
    found += 1
    let layer = window[kCGWindowLayer as String] as? Int ?? -1
    let alpha = window[kCGWindowAlpha as String] as? Double ?? -1
    let onScreen = window[kCGWindowIsOnscreen as String] as? Bool ?? false
    var bounds = "?"
    if let dict = window[kCGWindowBounds as String] as? [String: Any],
       let w = dict["Width"] as? Double, let h = dict["Height"] as? Double,
       let x = dict["X"] as? Double, let y = dict["Y"] as? Double {
        bounds = "\(Int(x)),\(Int(y)) \(Int(w))x\(Int(h))"
    }
    print("janela: owner=\(owner) layer=\(layer) alpha=\(alpha) onscreen=\(onScreen) bounds=\(bounds)")
}
print(found == 0 ? "NENHUMA janela do app encontrada" : "\(found) janela(s) do app na tela")
