import AppKit

let names = [
    "circle.lefthalf.filled",
    "circle.lefthalf.filled.inverse",
    "chevron.down",
    "chevron.up",
    "arrow.down.right",
    "xmark",
    "minus",
    "plus"
]
for name in names {
    let exists = NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    print("\(exists ? "ok  " : "MISS") \(name)")
}
