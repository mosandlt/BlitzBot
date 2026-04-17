import Foundation

enum Mode: String, CaseIterable, Identifiable, Codable {
    case normal, business, plus, rage, emoji, aiCommand, officeMode

    var id: String { rawValue }

    /// Voice-capable modes (driven by mic + Whisper). Excludes non-voice modes
    /// like `officeMode`, which uses a dedicated window instead of the recording HUD.
    static var voiceModes: [Mode] { allCases.filter { $0.isVoiceMode } }

    /// `true` when this mode is driven by microphone + Whisper. `false` for modes
    /// with a different input surface (e.g. `officeMode` takes file-drop + text).
    var isVoiceMode: Bool { self != .officeMode }

    var displayName: String {
        switch self {
        case .normal:     return String(localized: "mode.normal.name", defaultValue: "Normal")
        case .business:   return String(localized: "mode.business.name", defaultValue: "Business")
        case .plus:       return String(localized: "mode.plus.name", defaultValue: "Plus")
        case .rage:       return String(localized: "mode.rage.name", defaultValue: "Rage")
        case .emoji:      return String(localized: "mode.emoji.name", defaultValue: "Emoji")
        case .aiCommand:  return String(localized: "mode.aiCommand.name", defaultValue: "Prompt")
        case .officeMode: return String(localized: "mode.officeMode.name", defaultValue: "Office")
        }
    }

    var tagline: String {
        switch self {
        case .normal:     return String(localized: "mode.normal.tagline", defaultValue: "Sprache rein. Text raus.")
        case .business:   return String(localized: "mode.business.tagline", defaultValue: "Sprache rein. Businesstauglich raus.")
        case .plus:       return String(localized: "mode.plus.tagline", defaultValue: "Geschrieben sprechen.")
        case .rage:       return String(localized: "mode.rage.tagline", defaultValue: "Frust rein. Entspannt raus.")
        case .emoji:      return String(localized: "mode.emoji.tagline", defaultValue: "Sprache rein. Text mit Emojis raus.")
        case .aiCommand:  return String(localized: "mode.aiCommand.tagline", defaultValue: "Idee rein. Prompt raus.")
        case .officeMode: return String(localized: "mode.officeMode.tagline", defaultValue: "Datei rein. Zusammenfassung raus.")
        }
    }

    var symbolName: String {
        switch self {
        case .normal:     return "mic.fill"
        case .business:   return "briefcase.fill"
        case .plus:       return "text.justify.left"
        case .rage:       return "flame.fill"
        case .emoji:      return "face.smiling"
        case .aiCommand:  return "wand.and.stars"
        case .officeMode: return "doc.text.magnifyingglass"
        }
    }

    /// Returns the default system prompt localized for the target language.
    /// `language` is a 2-letter ISO code (`"de"`, `"en"`). Unknown codes fall back to German.
    func defaultSystemPrompt(for language: String = "de") -> String {
        language.lowercased().hasPrefix("en") ? defaultSystemPromptEnglish : defaultSystemPromptGerman
    }

    /// Back-compat accessor — defaults to German.
    var defaultSystemPrompt: String { defaultSystemPromptGerman }

    /// Used by the v1.0.4 prompt-migration to identify unchanged German defaults.
    var defaultSystemPromptGermanForMigration: String { defaultSystemPromptGerman }

    private var defaultSystemPromptGerman: String {
        switch self {
        case .officeMode:
            return """
            Du bekommst einen Text (entweder direkt getippt oder aus einer Datei geladen: Notiz, Protokoll, \
            Mail, Log, CSV, Code-Snippet, Dokumentation). Deine Aufgabe: eine strukturierte, präzise \
            Zusammenfassung für den Büro-Alltag.

            Gib in dieser Reihenfolge aus:
            1. Eine sehr kurze Einordnung in 1 Satz (was ist das Dokument).
            2. Die Kernaussagen als knappe Stichpunkte (nur was wirklich drin steht, nichts erfinden).
            3. Falls vorhanden: Entscheidungen, offene Punkte, nächste Schritte — je eigene Sektion, nur \
               wenn im Text tatsächlich genannt.
            4. Falls Zahlen/Daten/Deadlines/Namen im Text vorkommen: kurze Liste davon, unverändert.

            Regeln:
            - Keine Interpretation, keine Meinung, keine Empfehlungen die nicht im Text stehen.
            - Keine Einleitung ("Hier ist …"), keine Abschlussfloskel.
            - Nutze Markdown-Überschriften (##) und Stichpunkte (-).
            - Wenn der Text sehr kurz oder trivial ist: entsprechend knapp zusammenfassen, nicht \
              künstlich aufblasen.

            Antworte ausschließlich mit der Zusammenfassung.
            """
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

            WICHTIG — Neues Projekt vs. Update erkennen:
            Höre genau zu, ob der User ein brandneues Projekt starten will oder eine Änderung/Ergänzung \
            an etwas Bestehendem beschreibt. Im Zweifel: UPDATE annehmen, nicht neues Projekt. \
            Der User arbeitet meistens an existierendem Code/Content weiter.
            - Update-Signale: "ändere", "füge hinzu", "bau um", "erweitere", "fix", "in der Datei X", \
              "im bestehenden Y", "wir haben bereits", "aktuell macht das Z", Bezug auf konkreten \
              Bestand, Refactoring-Wortschatz.
            - Neues-Projekt-Signale: "starte ein neues", "bau mir ein", "komplett von null", \
              "erstelle ein neues Projekt/Repo/Skript".
            - Bei Update: formuliere den Prompt als Änderung an bestehendem Code. Mach klar, dass die \
              KI den vorhandenen Kontext respektieren soll (keine Umstrukturierung ohne Grund, keine \
              neuen Dateien wenn nicht nötig, bestehende Konventionen beibehalten). Nenne — falls \
              ableitbar — die betroffene(n) Datei(en) oder Komponente(n).
            - Bei neuem Projekt: beschreibe Scope, Stack, Strukturvorschlag.
            - Wenn komplett ambig und keine Signale zu finden: frame als Update und füge in die \
              "Offene Fragen" eine Frage ein, ob es neu oder Update ist.

            Regeln:
            - Ziel-Struktur (als Fließtext, keine Markdown-Headings): (1) Was geändert/ergänzt/ \
              gebaut werden soll — inkl. klarer Aussage ob Update an Bestehendem oder neues Projekt, \
              (2) Kontext / Umgebung / relevante Rahmenbedingungen, (3) Konkrete Anforderungen und \
              Constraints, (4) Akzeptanzkriterien oder erwartetes Ergebnis, (5) optional: \
              nennenswerte Edge-Cases.
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
        case .officeMode:
            return """
            You receive a text (typed directly or loaded from a file: note, meeting minutes, email, log, \
            CSV, code snippet, docs). Your job: produce a structured, precise summary for everyday office use.

            Output in this order:
            1. A very short one-sentence framing (what kind of document is this).
            2. The key points as concise bullets (only what's actually in the text — don't invent anything).
            3. If present: decisions, open items, next steps — each as its own section, only when \
               actually called out in the text.
            4. If the text contains numbers, dates, deadlines, or names: short list of those, unchanged.

            Rules:
            - No interpretation, no opinion, no recommendations that aren't in the text.
            - No preamble ("Here is …"), no closing filler.
            - Use markdown headings (##) and bullets (-).
            - If the text is very short or trivial: summarize accordingly, don't pad.

            Reply with the summary only.
            """
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

            IMPORTANT — detect new project vs. update:
            Listen carefully whether the user wants to start a brand-new project or describes a \
            change/addition to something that already exists. When in doubt: assume UPDATE, not new \
            project. The user is usually iterating on existing code/content.
            - Update signals: "change", "add", "refactor", "extend", "fix", "in file X", "in the \
              existing Y", "we already have", "currently it does Z", references to concrete existing \
              artifacts, refactoring vocabulary.
            - New-project signals: "start a new", "build me a", "from scratch", "create a new \
              project/repo/script".
            - On update: frame the prompt as a change to existing code. Make it clear the AI should \
              respect existing context (no unnecessary restructuring, no new files unless needed, \
              keep existing conventions). Name — if inferable — the affected file(s) or component(s).
            - On new project: describe scope, stack, proposed structure.
            - If fully ambiguous with no signals: frame as update and add a question in "Open \
              questions" asking whether it's new or an update.

            Rules:
            - Target structure (as flowing text, no markdown headings): (1) what to change / add / \
              build — including a clear statement of update vs. new project, (2) context / \
              environment / relevant constraints, (3) concrete requirements, (4) acceptance \
              criteria or expected result, (5) optional: notable edge cases.
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
