import AppKit

/// Headless checks for the window behaviour (resize math, collapse, transparency toggle).
/// Run with `--uitest`.
enum UiTest {
    static func run(controller: PiPPanelController, model: PlayerModel) {
        var failures = 0
        func check(_ name: String, _ condition: Bool, _ detail: String = "") {
            if condition {
                print("  ok   \(name)")
            } else {
                print("  FAIL \(name) \(detail)")
                failures += 1
            }
        }

        guard let window = controller.window else {
            print("  FAIL sem janela")
            NSApp.terminate(nil)
            return
        }
        let savedFrame = UserDefaults.standard.string(forKey: "panelFrame")
        let wasOverDock = model.bottomOverDock

        print("Resize (mesma matemática do grip)")
        let start = window.frame
        controller.resize(byDelta: CGSize(width: 60, height: -40))
        let afterResize = window.frame
        check("largura +60", abs(afterResize.width - (start.width + 60)) < 1, "\(start.width) → \(afterResize.width)")
        check("altura +40", abs(afterResize.height - (start.height + 40)) < 1, "\(start.height) → \(afterResize.height)")
        check("borda superior fixa", abs(afterResize.maxY - start.maxY) < 1, "maxY \(start.maxY) → \(afterResize.maxY)")
        check("canto inferior desce", afterResize.minY < start.minY, "\(start.minY) → \(afterResize.minY)")

        let tallFrame = afterResize
        print("Minimizar / expandir")
        model.toggleCollapsed()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let collapsed = window.frame
            check("altura colapsada = 36", abs(collapsed.height - 36) < 1, "\(collapsed.height)")
            check("largura preservada", abs(collapsed.width - tallFrame.width) < 1, "\(collapsed.width)")
            check("borda superior preservada", abs(collapsed.maxY - tallFrame.maxY) < 1)

            model.toggleCollapsed()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let restored = window.frame
                check("altura restaurada", abs(restored.height - tallFrame.height) < 1, "\(restored.height) vs \(tallFrame.height)")
                check("largura restaurada", abs(restored.width - tallFrame.width) < 1)

                print("Transparência")
                let before = model.transparentBackground
                model.toggleTransparency()
                check("alterna o fundo", model.transparentBackground != before)
                check("persiste em UserDefaults",
                      (UserDefaults.standard.object(forKey: "transparentBackground") as? Bool) == model.transparentBackground)
                model.toggleTransparency()

                print("Opacidade")
                model.setAlpha(0.75)
                check("alphaValue aplicado na janela", abs(window.alphaValue - 0.75) < 0.01, "\(window.alphaValue)")
                model.setAlpha(1.0)

                print("Posição na borda da tela")
                let screen = NSScreen.screens.first { $0.frame.intersects(window.frame) } ?? NSScreen.main
                let dockLine = screen?.visibleFrame.minY ?? 0
                let screenBottom = screen?.frame.minY ?? 0
                print("     visibleFrame.minY=\(dockLine) frame.minY=\(screenBottom)")

                func finish() {
                    if model.isDemo {
                        print("Transporte (demo)")
                        let playing = model.isPlaying
                        model.transport(.playPause)
                        check("play/pause alterna o estado", model.isPlaying != playing)
                        model.transport(.playPause)
                        check("play/pause volta ao estado original", model.isPlaying == playing)
                    }
                    if wasOverDock != model.bottomOverDock { model.toggleBottomOverDock() }
                    if let savedFrame { UserDefaults.standard.set(savedFrame, forKey: "panelFrame") }
                    else { UserDefaults.standard.removeObject(forKey: "panelFrame") }
                    print(failures == 0 ? "TUDO OK" : "\(failures) FALHA(S)")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { NSApp.terminate(nil) }
                }

                if model.bottomOverDock { model.toggleBottomOverDock() }
                controller.refreshPlacement()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    let withoutDock = window.frame
                    check("para 20 pt acima da Dock", abs(withoutDock.minY - (dockLine + 20)) < 2,
                          "minY=\(withoutDock.minY) esperado \(dockLine + 20)")

                    model.toggleBottomOverDock()
                    controller.refreshPlacement()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        let withDock = window.frame
                        check("desce até a borda com a opção ligada", abs(withDock.minY - (screenBottom + 6)) < 2,
                              "minY=\(withDock.minY) esperado \(screenBottom + 6)")
                        check("desceu de fato", withDock.minY < withoutDock.minY - 20,
                              "\(withoutDock.minY) → \(withDock.minY)")
                        finish()
                    }
                }
            }
        }
    }
}
