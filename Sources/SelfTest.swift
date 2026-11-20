import Foundation

/// Offline checks for the parsing / matching core. Run with `--selftest`.
enum SelfTest {
    static func run() -> Int32 {
        var failures = 0

        func check(_ name: String, _ condition: Bool, _ detail: String = "") {
            if condition {
                print("  ok   \(name)")
            } else {
                print("  FAIL \(name) \(detail)")
                failures += 1
            }
        }

        print("LRC parsing")
        let lrc = """
        [ar:Queen]
        [00:01.33] Is this the real life?
        [00:07.27] Caught in a landslide, no escape from reality
        [00:11.94][00:16.50] Open your eyes
        [00:19.30]<00:19.30>Look up to <00:19.90>the skies
        """
        let lines = LyricsService.parseLRC(lrc)
        check("descarta tags de metadados", lines.count == 5, "count=\(lines.count)")
        check("primeiro tempo 1.33", abs((lines.first?.time ?? 0) - 1.33) < 0.01, "\(lines.first?.time ?? -1)")
        check("timestamp duplo gera duas linhas", lines.filter { $0.text == "Open your eyes" }.count == 2)
        check("tag enhanced <mm:ss> removida", lines.contains { $0.text == "Look up to the skies" })
        check("ordenado por tempo", zip(lines, lines.dropFirst()).allSatisfy { $0.time <= $1.time })

        print("Matching / duração")
        let synced = syncSearch(title: "Bohemian Rhapsody", artist: "Queen", duration: 355)
        check("acha letra sincronizada", (synced?.lines.count ?? 0) > 20, "linhas=\(synced?.lines.count ?? 0)")
        check("marcada como sincronizada", synced?.synced == true)

        let live = syncSearch(title: "Príncipe da Paz", artist: "Flavio Vitor Jr.", duration: 509)
        check("responde para faixa brasileira", live != nil, "nil")
        check("prefere a versão de duração compatível", abs((live?.matchedDuration ?? 0) - 509) < 3,
              "casou com \(live?.matchedTitle ?? "-") (\(live?.matchedDuration ?? 0)s)")
        check("versão certa vem sincronizada", live?.synced == true)
        print("     casou: \(live?.matchedTitle ?? "-") @ \(Int(live?.matchedDuration ?? 0))s com \(live?.lines.count ?? 0) linhas")

        let junk = syncSearch(title: "zzzqqq faixa inexistente 12345", artist: "artista inexistente", duration: 100)
        check("faixa inexistente devolve vazio", (junk?.lines.count ?? 0) == 0)

        print(failures == 0 ? "TUDO OK" : "\(failures) FALHA(S)")
        return failures == 0 ? 0 : 1
    }

    private static func syncSearch(title: String, artist: String, duration: Double) -> LyricsPayload? {
        var payload: LyricsPayload?
        var finished = false
        _ = LyricsService.search(title: title, artist: artist, album: "", duration: duration) { result in
            switch result {
            case .success(let value): payload = value
            case .failure(let error): print("     erro de rede: \(error)")
            }
            finished = true
        }
        // The service answers on the main queue, so pump the run loop instead of blocking it.
        let deadline = Date().addingTimeInterval(25)
        while !finished && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        if !finished { print("     tempo esgotado") }
        return payload
    }
}
