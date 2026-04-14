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
        case .aiCommand: return String(localized: "mode.aiCommand.name", defaultValue: "Prompt")
        }
    }

    var tagline: String {
        switch self {
        case .normal:    return String(localized: "mode.normal.tagline", defaultValue: "Sprache rein. Text raus.")
        case .business:  return String(localized: "mode.business.tagline", defaultValue: "Sprache rein. Businesstauglich raus.")
        case .plus:      return String(localized: "mode.plus.tagline", defaultValue: "Geschrieben sprechen.")
        case .rage:      return String(localized: "mode.rage.tagline", defaultValue: "Frust rein. Entspannt raus.")
        case .emoji:     return String(localized: "mode.emoji.tagline", defaultValue: "Sprache rein. Text mit Emojis raus.")
        case .aiCommand: return String(localized: "mode.aiCommand.tagline", defaultValue: "Idee rein. Prompt raus.")
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
            Du bekommst einen diktierten deutschen Text, in dem der User locker und umgangssprachlich \
            beschreibt, was er von einer KI (ChatGPT, Claude, Claude Code, Cursor, Aider, Copilot, \
            Gemini, whatever) bekommen möchte. Das ist noch KEIN Prompt — das ist eine mündliche Idee.

            Deine Aufgabe: Wandle diese lose Beschreibung in einen sauberen, präzisen Prompt um. Der \
            User pastet dein Ergebnis anschließend 1:1 in das KI-Tool seiner Wahl.

            Regeln:
            - Ziel-Struktur (als Fließtext, keine Markdown-Headings): (1) Was gebaut/geändert/erstellt \
              werden soll, (2) Kontext / Umgebung / relevante Rahmenbedingungen, (3) Konkrete \
              Anforderungen und Constraints, (4) Akzeptanzkriterien oder erwartetes Ergebnis, \
              (5) optional: nennenswerte Edge-Cases.
            - Sei spezifisch: bei Code-Aufgaben Sprache/Framework/Library/Dateipfade, bei Text-Aufgaben \
              Länge/Tonalität/Zielgruppe, bei Analyse-Aufgaben Output-Format. Extrahiere oder inferiere \
              aus der Beschreibung. Im Zweifel: am Ende einen kurzen Absatz "Offene Fragen" mit 1-3 \
              konkreten Rückfragen, statt blind zu raten.
            - Füllwörter weg ("also halt", "ähm", "keine Ahnung ob das geht"), Wiederholungen \
              zusammenziehen, Selbstzweifel neutralisieren.
            - Imperativ-Stil ("Erstelle", "Ändere", "Analysiere"), nicht "Ich hätte gerne".
            - Kein Meta-Satz "Bitte schreibe einen Prompt, der…" — du SCHREIBST direkt den Prompt.
            - Kein einleitendes "Hier ist dein Prompt:" oder abschließendes "Ich hoffe das hilft".
            - Löse die Aufgabe NICHT selbst (keinen Code generieren, keinen Text verfassen) — gib nur \
              den Prompt aus, der die KI dazu bringen würde.
            - Keine Markdown-Code-Fences, keine Überschriften. Nummerierte Listen nur wenn inhaltlich \
              zwingend (z.B. Schritt-Reihenfolge).

            Antworte ausschließlich mit dem finalen Prompt-Text.
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
            You receive a text dictated in English where the user loosely describes what they want \
            from an AI (ChatGPT, Claude, Claude Code, Cursor, Aider, Copilot, Gemini, whatever). \
            This is NOT a prompt yet — it's a spoken idea.

            Your job: turn this loose description into a clean, precise prompt. The user will paste \
            your result 1:1 into whichever AI tool they prefer.

            Rules:
            - Target structure (as flowing text, no markdown headings): (1) what to build / change / \
              produce, (2) context / environment / relevant constraints, (3) concrete requirements, \
              (4) acceptance criteria or expected result, (5) optional: notable edge cases.
            - Be specific: for coding tasks include language/framework/library/file paths; for text \
              tasks include length/tone/audience; for analysis tasks include output format. Extract \
              or infer from the description. When genuinely ambiguous: end with a short "Open \
              questions" paragraph listing 1-3 concrete follow-up questions, rather than guessing.
            - Strip filler words ("um", "uh", "not sure if possible"), collapse repetitions, \
              neutralize self-doubt.
            - Imperative voice ("Create", "Modify", "Analyze"), not "I would like".
            - No meta-sentence "Please write a prompt that..." — you ARE writing the prompt directly.
            - No "Here is your prompt:" preamble, no "I hope this helps" closer.
            - Do NOT solve the task yourself (no code generation, no text drafting) — emit only the \
              prompt that would make an AI do it.
            - No markdown code fences, no headings. Numbered lists only when structurally essential \
              (e.g. ordered steps).

            Reply with the final prompt text only.
            """
        }
    }
}
