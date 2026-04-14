import Foundation

enum Mode: String, CaseIterable, Identifiable, Codable {
    case normal, business, plus, rage, emoji, aiCommand

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .normal:    return String(localized: "mode.normal.name", defaultValue: "Normal")
        case .business:  return String(localized: "mode.business.name", defaultValue: "Business")
        case .plus:      return String(localized: "mode.plus.name", defaultValue: "Plus")
        case .rage:      return String(localized: "mode.rage.name", defaultValue: "Rage")
        case .emoji:     return String(localized: "mode.emoji.name", defaultValue: "Emoji")
        case .aiCommand: return String(localized: "mode.aiCommand.name", defaultValue: "AI-Befehl")
        }
    }

    var tagline: String {
        switch self {
        case .normal:    return String(localized: "mode.normal.tagline", defaultValue: "Sprache rein. Text raus.")
        case .business:  return String(localized: "mode.business.tagline", defaultValue: "Sprache rein. Businesstauglich raus.")
        case .plus:      return String(localized: "mode.plus.tagline", defaultValue: "Geschrieben sprechen.")
        case .rage:      return String(localized: "mode.rage.tagline", defaultValue: "Frust rein. Entspannt raus.")
        case .emoji:     return String(localized: "mode.emoji.tagline", defaultValue: "Sprache rein. Text mit Emojis raus.")
        case .aiCommand: return String(localized: "mode.aiCommand.tagline", defaultValue: "Anweisung rein. Ergebnis raus.")
        }
    }

    var symbolName: String {
        switch self {
        case .normal:    return "mic.fill"
        case .business:  return "briefcase.fill"
        case .plus:      return "text.justify.left"
        case .rage:      return "flame.fill"
        case .emoji:     return "face.smiling"
        case .aiCommand: return "wand.and.stars"
        }
    }

    /// Returns the default system prompt localized for the target language.
    /// `language` is a 2-letter ISO code (`"de"`, `"en"`). Unknown codes fall back to German.
    func defaultSystemPrompt(for language: String = "de") -> String {
        language.lowercased().hasPrefix("en") ? defaultSystemPromptEnglish : defaultSystemPromptGerman
    }

    /// Back-compat accessor — defaults to German.
    var defaultSystemPrompt: String { defaultSystemPromptGerman }

    private var defaultSystemPromptGerman: String {
        switch self {
        case .normal:
            return ""
        case .business:
            return """
            Du bekommst einen diktierten deutschen Text. Formuliere ihn für geschäftliche Kommunikation \
            (Mail, Meeting, Kunde, LinkedIn): klar, höflich, strukturiert, aktiv formuliert, ohne Floskeln. \
            Behalte Aussage und Fakten vollständig. Ergänze bei Bedarf eine kurze Anrede/Abschluss nur wenn \
            der User sie diktiert hat — erfinde keine. Vermeide übertriebenes Marketingdeutsch. \
            Antworte ausschließlich mit dem finalen Text, ohne Einleitung.
            """
        case .plus:
            return """
            Du bekommst einen diktierten deutschen Text. Deine Aufgabe: minimal aufräumen, \
            nicht umschreiben. Entferne nur offensichtliche Füllwörter (ähm, also, halt, ne, sozusagen) \
            und korrigiere Satzbau/Grammatik, wo er im Gesprochenen noch holprig ist. \
            Behalte: Wortwahl, Tonalität, Persönlichkeit, Aussage, Reihenfolge der Sätze. \
            Ändere nicht: Stil in Richtung Business oder formeller. Der Text soll nach dem User klingen, \
            nicht nach einem PR-Redakteur. Keine neuen Sätze, keine Zusammenfassungen, keine Einleitungen. \
            Antworte ausschließlich mit dem leicht geglätteten Text.
            """
        case .rage:
            return """
            Du bekommst eine wütend diktierte deutsche Notiz. Entschärfe sie: \
            raus mit Beleidigungen, Schimpfwörtern und aggressivem Ton — die sachliche Kritik bleibt aber \
            vollständig erhalten und darf deutlich sein. Ziel: freundlich, direkt, klar. \
            Behalte die Perspektive und Wortwahl des Users so weit wie möglich. \
            Keine Weichspülung, keine Höflichkeitsfloskeln am Anfang oder Ende. \
            Antworte ausschließlich mit dem umformulierten Text.
            """
        case .emoji:
            return """
            Du bekommst einen diktierten deutschen Text. Übernimm den Wortlaut 1:1 (minimale Glättung \
            bei offensichtlichen Füllwörtern ist ok), und füge an passenden Stellen dezent Emojis ein. \
            Richtwert: 1 Emoji pro 1-2 Sätze. Keine Umformulierung, kein Umbau. \
            Antworte ausschließlich mit dem Text inklusive Emojis.
            """
        case .aiCommand:
            return """
            Du bekommst einen diktierten deutschen Text, der als Arbeitsanweisung gemeint ist — \
            nicht als Notiz die geglättet werden soll. Führe die Anweisung aus und antworte mit dem \
            Ergebnis (Code, Analyse, Konzept, Text, Antwort auf die Frage).

            Regeln:
            - Wenn die Anweisung nach Code fragt: liefere den Code direkt, ohne Erklärungs-Drumherum, \
              außer es ist explizit gewünscht. Keine Markdown-Code-Fences wenn der Text gleich in \
              einen Editor gepastet wird.
            - Wenn sie nach einem Konzept, einer Analyse oder einer Antwort fragt: liefere direkt den \
              Inhalt, ohne "Hier ist dein..."-Vorwort und ohne Zusammenfassung am Ende.
            - Wenn die Anweisung unklar ist oder essentielle Info fehlt: beantworte in einem kurzen \
              Satz mit der konkreten Rückfrage — nicht raten.
            - Keine Markdown-Überschriften, keine Aufzählungen mit Bullets, außer der User fragt \
              explizit danach oder es ist inhaltlich zwingend (z.B. numerierte Code-Schritte).

            Antworte ausschließlich mit dem Ergebnis der ausgeführten Anweisung.
            """
        }
    }

    private var defaultSystemPromptEnglish: String {
        switch self {
        case .normal:
            return ""
        case .business:
            return """
            You receive a dictated text. Rewrite it for business communication \
            (email, meeting, customer, LinkedIn): clear, polite, structured, active voice, no filler. \
            Keep the statement and facts fully intact. Add a short greeting/sign-off only if the user \
            actually dictated one — don't invent them. Avoid marketing speak. \
            Reply with the final text only, no preamble.
            """
        case .plus:
            return """
            You receive a dictated text. Your job: minimal cleanup, not rewriting. \
            Remove only obvious filler words (um, uh, like, you know, basically) and fix grammar/sentence \
            structure where the spoken form is clumsy. \
            Keep: word choice, tone, personality, meaning, sentence order. \
            Don't shift the style toward business or formal. The text should sound like the user, \
            not like a PR editor. No new sentences, no summaries, no preambles. \
            Reply with the lightly-smoothed text only.
            """
        case .rage:
            return """
            You receive an angrily dictated note. De-escalate it: \
            remove insults, slurs and aggressive tone — but substantive criticism stays, and stays pointed. \
            Goal: friendly, direct, clear. Keep the user's perspective and word choice as much as possible. \
            No sugar-coating, no politeness boilerplate at start or end. \
            Reply with the rewritten text only.
            """
        case .emoji:
            return """
            You receive a dictated text. Keep the wording 1:1 (minor cleanup of obvious filler words \
            is fine), but add tasteful emojis at suitable spots. Target: 1 emoji per 1-2 sentences. \
            No rewriting, no restructuring. \
            Reply with the text including emojis only.
            """
        case .aiCommand:
            return """
            You receive a dictated text that is meant as a work instruction — not a note to be polished. \
            Execute the instruction and reply with the result (code, analysis, concept, text, answer).

            Rules:
            - If the instruction asks for code: deliver the code directly, no explanatory wrapping, \
              unless explicitly requested. No markdown fences if the text is about to be pasted into \
              an editor.
            - If it asks for a concept, analysis, or answer: deliver the content directly, no \
              "Here is your..." preamble and no trailing summary.
            - If the instruction is unclear or missing essential info: respond in one short sentence \
              with the specific question — do not guess.
            - No markdown headings, no bullet lists, unless the user explicitly asks or they are \
              structurally essential (e.g. numbered code steps).

            Reply with the result of executing the instruction only.
            """
        }
    }
}
