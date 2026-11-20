import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let model = PlayerModel()
    private var panel: PiPPanelController?

    private var transparencyItem: NSMenuItem?
    private var collapseItem: NSMenuItem?
    private var overDockItem: NSMenuItem?
    private var opacityItems: [NSMenuItem] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()

        let controller = PiPPanelController(model: model)
        panel = controller
        controller.present()
        model.start()

        if CommandLine.arguments.contains("--uitest") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [model] in UiTest.run(controller: controller, model: model) }
            return
        }

        if let index = CommandLine.arguments.firstIndex(of: "--snapshot"),
           index + 1 < CommandLine.arguments.count {
            let path = CommandLine.arguments[index + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                let ok = Snapshot.capture(window: controller.window!, to: path)
                print(ok ? "snapshot: \(path)" : "snapshot falhou")
                NSApp.terminate(nil)
            }
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "music.note.list", accessibilityDescription: "Letras do Spotify")
            image?.isTemplate = true
            button.image = image
        }

        let menu = NSMenu()
        menu.delegate = self

        add(menu, "Mostrar / ocultar letras", #selector(togglePanel), "l")
        let collapse = add(menu, "Minimizar janela", #selector(toggleCollapse), "m")
        collapseItem = collapse

        menu.addItem(.separator())

        let transparency = add(menu, "Fundo transparente", #selector(toggleTransparency), "t")
        transparencyItem = transparency

        let overDock = add(menu, "Descer até a borda da tela", #selector(toggleOverDock), "d")
        overDockItem = overDock

        let opacityRoot = NSMenuItem(title: "Opacidade da janela", action: nil, keyEquivalent: "")
        let opacityMenu = NSMenu()
        for (title, value) in [("100%", 1.0), ("90%", 0.9), ("75%", 0.75), ("60%", 0.6), ("40%", 0.4)] {
            let entry = NSMenuItem(title: title, action: #selector(setOpacity(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = value
            opacityMenu.addItem(entry)
            opacityItems.append(entry)
        }
        opacityRoot.submenu = opacityMenu
        menu.addItem(opacityRoot)

        menu.addItem(.separator())

        add(menu, "Tocar / pausar", #selector(playPause), "p")
        add(menu, "Faixa anterior", #selector(previousTrack), String(UnicodeScalar(UInt32(NSLeftArrowFunctionKey))!))
        add(menu, "Próxima faixa", #selector(nextTrack), String(UnicodeScalar(UInt32(NSRightArrowFunctionKey))!))

        menu.addItem(.separator())

        add(menu, "Adiantar letra (0,25 s)", #selector(offsetForward), "]")
        add(menu, "Atrasar letra (0,25 s)", #selector(offsetBackward), "[")
        add(menu, "Zerar ajuste da letra", #selector(offsetReset), "")

        menu.addItem(.separator())

        add(menu, "Recarregar letra", #selector(reloadLyrics), "r")
        add(menu, "Restaurar tamanho da janela", #selector(resetSize), "")

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Sair", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }

    // MARK: - Menu state

    func menuNeedsUpdate(_ menu: NSMenu) {
        transparencyItem?.state = model.transparentBackground ? .on : .off
        overDockItem?.state = model.bottomOverDock ? .on : .off
        collapseItem?.title = model.isCollapsed ? "Expandir janela" : "Minimizar janela"
        for item in opacityItems {
            let value = item.representedObject as? Double ?? 1.0
            item.state = abs(value - model.windowAlpha) < 0.01 ? .on : .off
        }
    }

    // MARK: - Actions

    @objc private func togglePanel() {
        panel?.toggle()
    }

    @objc private func toggleCollapse() {
        model.toggleCollapsed()
    }

    @objc private func toggleTransparency() {
        model.toggleTransparency()
    }

    @objc private func setOpacity(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        model.setAlpha(value)
    }

    @objc private func toggleOverDock() {
        model.toggleBottomOverDock()
        panel?.refreshPlacement()
    }

    @objc private func playPause() {
        model.transport(.playPause)
    }

    @objc private func previousTrack() {
        model.transport(.previous)
    }

    @objc private func nextTrack() {
        model.transport(.next)
    }

    @objc private func offsetForward() {
        model.nudgeOffset(0.25)
    }

    @objc private func offsetBackward() {
        model.nudgeOffset(-0.25)
    }

    @objc private func offsetReset() {
        model.resetOffset()
    }

    @objc private func reloadLyrics() {
        model.reloadLyrics()
    }

    @objc private func resetSize() {
        panel?.resetSize()
    }
}
